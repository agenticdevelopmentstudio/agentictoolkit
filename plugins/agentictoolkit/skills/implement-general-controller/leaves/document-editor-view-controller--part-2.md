<!-- leaf: implement-general-controller/document-editor-view-controller--part-2 · source: document-editor-view-controller.md -->

# DocumentEditorViewController — continued (part 2)

## Accessibility

- **Role/trait**: The container view is a plain `NSView` (via `NSHostingView` inside an `NSStackView`) with no explicit accessibility role override in this file. The four gear-popover rows carry the accessibility identifiers `document.options.line-numbers`, `document.options.overview`, `document.options.invisibles`, and `document.options.reset` (see **toggle-accessibility-identifiers**, **reset-accessibility-identity**). The breadcrumb's own accessibility identifiers and role are out of scope (see its own recipe).
- **Label requirements**: The reset button's accessibility label is set explicitly to `"Reset Editor Options to Defaults"`, distinct from its visible title `"Reset to Defaults"`. The three toggle rows' own accessibility labels are set by `WindowOptionsToggle` (out of scope for this recipe).
- **Announce state changes**: When the displayed file changes — restored on construction, set through `fileURL`, or cleared through `clearDocument()` — this file posts no accessibility notification of its own (e.g., a layout-changed or announcement notification) around the breadcrumb rebuild and editor-content swap. The only signal it produces is `onTitleChange`, consumed by the enclosing tab chrome (out of scope) to update its own title label; whether a VoiceOver user tracking this pane is told the displayed file changed depends entirely on that enclosing chrome's own label update.
- **Minimum tap target**: Not applicable: this controller targets macOS pointer and trackpad input, not touch. No minimum width or height is set on the reset button or the toggle rows by this file, and macOS's HIG does not mandate a touch-target minimum for pointer-driven chrome the way iOS does for touch.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `store` | `PaneStateStore` | required at init | Where the displayed file's path is read and written under `fileURLKey`. `EphemeralPaneStateStore` forgets its values when deallocated; a project window supplies a store backed by durable local storage instead (see Privacy, Storage). |
| `documentStore` | `TextDocumentStore` | required at init | Passed through unchanged to the hosted `FileEditorView` (out of scope). |
| `saveScheduler` | `TextDocumentSaveScheduler` | required at init | Passed through unchanged to the hosted `FileEditorView` (out of scope). |
| `languageServices` | `ProjectLanguageServices?` | required at init (may be `nil`) | Passed through unchanged to the hosted `FileEditorView` (out of scope). |
| `rootURL` | `URL` | required at init | The project root the breadcrumb computes its crumbs relative to; handed to `BreadcrumbView` at construction and never changed afterward. |
| `options` | `EditorOptionsOverride` | created at init from `store` | This pane's independent override of the three editor display toggles; publicly readable, not settable. |
| `fileURL` | `URL?` | `nil`, or restored from `store` at init | The file currently displayed. Setting it updates the selection, the breadcrumb, and the store, and fires `onTitleChange`. |
| `onTitleChange` | `(() -> Void)?` | `nil` | Called after every change to the displayed file. |
| `paneTitle` | `String` | `fileURL`'s last path component, or `"Untitled"` | Read-only; see **pane-title-is-filename**, **pane-title-untitled-when-empty**. |
| `onPaneTitleChange` | `(() -> Void)?` | `nil` | Getter/setter bridge onto `onTitleChange`; see **title-change-callback-bridge**. |
| `onOpenRequest` | `((URL) -> Void)?` | `nil` | Called with a URL the breadcrumb or the hosted editor resolved but did not open in place. |

### Methods

| Method | Description |
|--------|-------------|
| `clearDocument()` | Sets `fileURL` to `nil` and persists that, without removing the pane; see **clear-document-preserves-pane**. |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal string) | "Untitled" | `paneTitle` when no file is displayed. |
| (none — literal string) | "Show line numbers" | First gear-popover toggle's title. |
| (none — literal string) | "Show overview" | Second gear-popover toggle's title. |
| (none — literal string) | "Show invisibles" | Third gear-popover toggle's title. |
| (none — literal string) | "Reset to Defaults" | Reset button's visible title. |
| (none — literal string) | "Reset Editor Options to Defaults" | Reset button's accessibility label. |

No localization key or `String(localized:)`/`.strings`-catalog mechanism exists for any user-facing string in this file — every string above is a hardcoded English literal.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: every method in this file (`show`, `clearDocument`, `refreshOptionRows`) mutates views immediately with no `NSAnimationContext`, layer animation, or transition, so there is no motion for this setting to reduce. |
| Increase Contrast | Not observed in this file: the hosted content's background and foreground colors are resolved through the theme system via `.themedRoot()`; any contrast adaptation belongs to that system, out of this ingredient's scope. |
| Differentiate Without Color | Not applicable: no state in this file is conveyed by color alone. The reset button's enabled/disabled state uses AppKit's own standard button-disabled rendering (not a custom color-only cue), and each toggle's checked state is conveyed by its checkbox glyph, not by color. |

## Privacy

- **Data collected**: This file introduces no new data collection beyond the file path the user is already viewing in this window. No personal or sensitive data is read or written by this file itself.
- **Storage**: Local only, through the caller-supplied `PaneStateStore`, under the key `fileURLKey`. The concrete store's durability is opaque to this file: `EphemeralPaneStateStore` (used in tests, and for a container with nothing to persist) forgets its values as soon as it is deallocated, while a project window's own store persists `pane_state` beyond app restarts. This file specifies only that it writes/reads that one key; the durability guarantee is the store's, not this file's.
- **Transmission**: None. No network call appears anywhere in this file.
- **Retention**: Tied to the given `store`'s own retention policy; this file's only retention-relevant action is writing `nil` for `fileURLKey` when the document is cleared or the stored file no longer exists (see **clear-document-preserves-pane**, **missing-file-restore**).

