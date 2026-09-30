<!-- leaf: implement-file/editor-view--states · source: file-editor-view.md -->

# FileEditorView

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
