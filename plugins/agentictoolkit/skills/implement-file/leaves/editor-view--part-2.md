<!-- leaf: implement-file/editor-view--part-2 · source: file-editor-view.md -->

# FileEditorView — continued (part 2)

## Accessibility

- **Role/trait**: `FileEditorView.swift` sets no explicit accessibility role, trait, or identifier anywhere in this file. The placeholder's `Text` and `Image(systemName: "doc.text")` carry SwiftUI's automatic default behavior (a spoken static-text element, and a label derived from the SF Symbol's name) — neither is overridden or suppressed. The mounted `SourceEditor`'s and `QuickLookPreview`'s own accessibility behavior is out of scope for this recipe.
- **Label requirements**: No `.accessibilityLabel`, `.accessibilityValue`, or `.accessibilityHint` modifier appears anywhere in `FileEditorView.swift`; the placeholder relies entirely on SwiftUI's automatic labels for its `Text` and `Image`.
- **Announce state changes**: Switching `display` between empty, loading, text, QuickLook, and unavailable replaces the content shown inside the one always-mounted `FileEditorContentView`, but neither `FileEditorView.swift` nor `FileEditorState.swift` posts any explicit accessibility notification (e.g., a layout-changed or screen-changed post) when that switch happens; a VoiceOver user is told about the new content only if SwiftUI/AppKit's own automatic change detection picks it up on its own.
- **Minimum tap target**: Not applicable: `FileEditorView` targets macOS pointer and keyboard input and defines no tappable or clickable control of its own; the mounted editor's and QuickLook's own hit targets are out of scope.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `selectedNode` | `FileTreeNode?` | required, supplied by the caller on every render | The file-tree node to show; `nil`, a directory, or a package clears the editor. |
| `documentStore` | `TextDocumentStore` | required at init | The app-wide, reference-counted open-document registry; shared across every editor pane in the app. |
| `saveScheduler` | `TextDocumentSaveScheduler` | required at init | The app-wide debounced autosave scheduler; shared across every editor pane. |
| `languageServices` | `ProjectLanguageServices?` | required at init (may be `nil`) | This project's language servers; `nil` disables completion, jump-to-definition, semantic highlighting, and diagnostic annotations for every document this pane opens. |
| `options` | `EditorOptionsOverride` | required at init | This pane's resolved line-numbers/minimap ("overview")/invisible-characters display settings; a later change reaches every mounted editor live. |
| `openFile` | `(@MainActor (URL) -> Void)?` | required at init (may be `nil`) | Callback for showing a cross-file go-to-definition target; `nil` disables jump-to-definition for every document this pane opens. |

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

## Privacy

- **Data collected**: None of its own beyond the file the user has already selected in the file browser. The component reads that file's bytes into memory to display and, for text, into an editable buffer; it collects nothing else.
- **Storage**: Local disk only. Edits are written back to the same file the user opened, through the injected `TextDocumentSaveScheduler`'s debounced autosave; the in-memory cache (up to 8 documents, plus their undo history) lives only as long as this view does and is not itself persisted.
- **Transmission**: None from this component. Project language-server communication (completion, jump-to-definition, diagnostics), when `languageServices` is supplied, is a local inter-process exchange with a language server, not a network call.
- **Retention**: A file's content on disk persists per the file system's own guarantees, subject to the debounce window stated under Autosave & Persistence and the retry behavior described in Design Decisions. The in-memory cache retains a document only until it is evicted (least-recently-selected, past 8 documents) or this pane is deallocated, at which point its pending autosave is flushed and its reference released — nothing is retained beyond that.

## Platform Notes

- **SwiftUI**: This is the source implementation: `FileEditorView.swift`, `FileEditorState.swift`, and `FilePreviewLoader.swift` (all in `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Views/`). `FileEditorView` is a thin SwiftUI shell around a `@StateObject` `FileEditorState`; the actual multi-document cache is a file-private `CachedEditorStack` (`NSViewRepresentable`) backed by `CachedEditorStackView`, a plain `NSView` holding one `NSHostingView<AnyView>` per cached document, each wrapping a `CodeEditSourceEditor.SourceEditor`. Non-text content is shown through `QuickLookPreview.swift`, a separate `NSViewRepresentable` around `QLPreviewView` (out of scope for this recipe).
- **Compose**: There is no Compose analogue to a persistently-mounted native view tree kept alive independent of the composition — Compose recomposes and can discard a composable's UI entirely when it leaves the tree. Reproduce the "undo survives switching files" requirement by keeping each open document's text buffer and undo state in a `ViewModel` (or `rememberSaveable`-backed holder) keyed by URI, scoped to the pane rather than to the composable, and drive visibility with `Modifier` (not adding/removing the composable from the tree) so an inactive editor's Compose state is preserved rather than torn down and rebuilt — the closest available parallel to `isHidden` never destroying the AppKit host.
- **React/Web**: Mount one code-editor instance (e.g., CodeMirror or Monaco) per open document in the DOM, and toggle the inactive ones with `display: none` — the CSS property that, like `isHidden`, also excludes the element from hit-testing and (paired with `inert` or `tabindex="-1"`) from the tab order — rather than mounting/unmounting per selection, which would recreate the editor and lose its undo history exactly as an `.id()`-forced SwiftUI remount did here. Reproduce the 8-MiB/UTF-8 classification and the QuickLook fallback with a browser file-type/size check that routes to an `<img>`/`<video>`/`<iframe>`(PDF) preview, or a "no preview available" placeholder, in place of QuickLook.
- **AppKit / UIKit**: This recipe's macOS implementation already is the AppKit/SwiftUI-hybrid pattern to follow (`CachedEditorStackView`); a UIKit (iOS) port would replace it with a `UIViewController`-containment stack — one child view controller per cached document, added via `addChild(_:)` and shown/hidden with `UIView.isHidden` (which, like AppKit's, excludes a view from both hit-testing and first-responder eligibility) — and would present non-text content with `QLPreviewController` (embedded via containment, or presented modally) in place of the macOS-only `QLPreviewView`.
- **WinUI 3**: There is no single WinUI 3 control that is this whole component's analogue; compose it from a `Grid` or `Frame` holding one child `UIElement` per cached document in a dictionary keyed by URI (mirroring `hostsByURI`), each hosting either a native text control (e.g., a syntax-highlighting `TextBox`/`RichEditBox`, or a `WebView2` hosting Monaco) or a preview surface for non-text content, since WinUI has no built-in QuickLook equivalent (a Shell preview-handler COM interop, or a `WebView2` navigated to the file, is the closest available substitute). Toggle which child is shown with `UIElement.Visibility = Visible`/`Collapsed`, never `Opacity = 0` — `Opacity` in WinUI, like `alphaValue` in AppKit, does not remove an element from hit-testing or from the tab-focus chain, which is exactly the bug `isHidden` exists here to avoid (see Design Decisions). Drive the placeholder/loading/text/preview/unavailable branches from a view-model enum mirroring `FileEditorState.Display`, bound to each branch's `Visibility`, and implement the 1-second-debounced autosave with a `DispatcherTimer` restarted on every text-changed event, matching `TextDocumentSaveScheduler`'s per-key debounce.

