<!-- leaf: implement-general-controller/document-editor-view-controller--states · source: document-editor-view-controller.md -->

# DocumentEditorViewController

## States

| State | Appearance change |
|-------|------------------|
| Default | Editor shows the file at `fileURL`, or an empty editor state (delegated to `FileEditorView`, out of scope) when `fileURL` is `nil` |
| Pressed | Not applicable: this class is a container. The reset button's and toggles' own pressed appearance is drawn by AppKit/`WindowOptionsToggle`, out of scope for this recipe. |
| Disabled | Not applicable to the container itself; the reset button is individually enabled or disabled (see **reset-button-enabled-matches-override**) — not the whole editor. |
| Focused | Not applicable: this file sets no custom focus-ring drawing; keyboard focus on its buttons and toggles is AppKit's own default rendering. |
| Loading | Not applicable: every method in this file is synchronous. Any asynchronous loading of file content belongs to `FileEditorView`/`TextDocumentStore`, out of scope. |
| File open | Breadcrumb shows the path from `rootURL` to `fileURL`; `paneTitle` is the file's last path component. |
| No file (`fileURL == nil`) | Breadcrumb is empty; `paneTitle` is `"Untitled"`. |
| An option overridden in this pane | The gear popover's reset button is enabled (`isEnabled == true`); the overridden toggle(s) reflect the pane-local value rather than the app-wide setting. |
| No option overridden in this pane | The reset button is disabled; every toggle reflects the app-wide setting. |
