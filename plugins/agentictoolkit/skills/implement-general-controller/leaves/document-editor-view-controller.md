<!-- leaf: implement-general-controller/document-editor-view-controller · source: document-editor-view-controller.md -->

**Rules** (cite as `implement-general-controller/document-editor-view-controller#<slug>`):

- `file-url-key-constant` MUST
- `own-file-selection` MUST
- `coder-init-unsupported` MUST
- `restore-on-construction` MUST
- `missing-file-restore` MUST
- `restore-omits-redundant-write` MUST
- `construction-title-change` MUST
- `file-url-reflects-selection` MUST
- `set-file-url-updates-selection` MUST
- `set-file-url-persists` MUST
- `set-file-url-updates-breadcrumb` MUST
- `file-url-title-change` MUST
- `directory-detected-via-resource-value` MUST
- `clear-document-preserves-pane` MUST
- `pane-title-is-filename` MUST
- `pane-title-untitled-when-empty` MUST
- `title-change-callback-bridge` MUST
- `options-rows-order` MUST
- `toggle-initial-state-resolved` MUST
- `toggle-change-writes-override` MUST
- `reset-button-label-and-style` MUST
- `reset-button-enabled-matches-override` MUST
- `reset-button-action` MUST
- `reset-accessibility-identity` MUST
- `toggle-accessibility-identifiers` MUST
- `rows-refresh-on-options-change` MUST
- `pane-override-isolated` MUST
- `reset-does-not-affect-other-panes-or-global` MUST
- `breadcrumb-above-content` MUST
- `breadcrumb-fixed-height` MUST
- `content-spans-container-width` MUST
- `root-view-initial-frame` MUST
- `content-uses-themed-root` MUST
- `hosts-file-editor-view` MUST
- `breadcrumb-selection-routes-out` MUST
- `editor-open-request-routes-out` MUST

# DocumentEditorViewController

## Overview

`DocumentEditorViewController` (`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/DocumentPane/DocumentEditorViewController.swift`) is one editor inside one pane of one tab. It hosts a `BreadcrumbView` above a `FileEditorView` (each out of this recipe's scope; see their own recipes) and holds its own `FileBrowserSelection` rather than sharing the browser's, so two editors open side by side in the same window can each show a different file. It restores the last file it showed from a caller-supplied `PaneStateStore`, exposes a per-pane override of the editor's three display toggles (line numbers, overview, invisibles) through `PaneOptionsProviding`, exposes its title through `PaneTitleProviding`, and routes any file it cannot open itself — a breadcrumb choice, a go-to-definition target — outward through `onOpenRequest` rather than opening it in place, because the file browser's own selection is the one place that decides what is open across the whole window.

## Behavioral Requirements

### Identity & Construction

- **file-url-key-constant**: `DocumentEditorViewController.fileURLKey` MUST equal the literal string `"fileURL"`.
- **own-file-selection**: The component MUST hold its own `FileBrowserSelection` instance, distinct from any other `DocumentEditorViewController`'s selection, so that two editors can display two different files at once.
- **coder-init-unsupported**: The component MUST NOT support `NSCoder`-based initialization; invoking `init(coder:)` MUST call `fatalError`.
- **restore-on-construction**: During initialization, the component MUST read `store.paneStateValue(forKey: fileURLKey)` and, when a value is present and its file exists on disk, MUST display that file.
- **missing-file-restore**: When the stored path's file does not exist on disk (per `FileManager.default.fileExists(atPath:)`), the component MUST clear the stored value for `fileURLKey` and leave `fileURL` as `nil`, rather than displaying or erroring on a missing file.
- **restore-omits-redundant-write**: Restoring a stored file during initialization MUST NOT write that same value back to the store; only a subsequent call that changes the displayed file MUST write to the store.
- **construction-title-change**: Restoring a stored file during initialization MUST also invoke `onTitleChange` afterward, the same as any other call that changes the displayed file.

### Displaying and Changing the File

- **file-url-reflects-selection**: The `fileURL` property MUST return the `url` of the currently selected file-browser node, or `nil` when no node is selected.
- **set-file-url-updates-selection**: Setting `fileURL` to a non-nil value MUST set the selection to a node for that URL; setting it to `nil` MUST clear the selection.
- **set-file-url-persists**: Setting `fileURL` MUST write the new value — the URL's path, or `nil` — to the store under `fileURLKey`.
- **set-file-url-updates-breadcrumb**: Setting `fileURL` MUST set the breadcrumb's `fileURL` to the same value.
- **file-url-title-change**: Setting `fileURL` MUST invoke `onTitleChange` afterward.
- **directory-detected-via-resource-value**: The component MUST determine whether a URL being shown is a directory by querying its `.isDirectoryKey` resource value, defaulting to `false` when that query fails, rather than assuming the URL is a file because of how it was obtained.
- **clear-document-preserves-pane**: `clearDocument()` MUST set `fileURL` to `nil` and persist that clearing, and MUST NOT remove the pane or otherwise affect anything beyond the displayed file.

### Pane Title

- **pane-title-is-filename**: `paneTitle` MUST equal `fileURL`'s last path component when `fileURL` is non-nil.
- **pane-title-untitled-when-empty**: `paneTitle` MUST equal the literal string `"Untitled"` when `fileURL` is `nil`.
- **title-change-callback-bridge**: `onPaneTitleChange`'s getter and setter MUST read and write the same underlying closure as `onTitleChange`.

### Editor Options Popover

- **options-rows-order**: `makePaneOptionRows()` MUST return exactly four views, in order: the "Show line numbers" toggle, the "Show overview" toggle, the "Show invisibles" toggle, then the reset button.
- **toggle-initial-state-resolved**: Each toggle's `isOn` at the moment `makePaneOptionRows()` builds it MUST equal the corresponding resolved value on `options` (`showLineNumbers`, `showOverview`, `showInvisibles`).
- **toggle-change-writes-override**: Changing a toggle's value MUST call the matching `options.setShowLineNumbers(_:)`, `options.setShowOverview(_:)`, or `options.setShowInvisibles(_:)` with the new value.
- **reset-button-label-and-style**: The fourth row MUST be an `NSButton` titled `"Reset to Defaults"` with `bezelStyle` `.rounded`.
- **reset-button-enabled-matches-override**: The reset button's `isEnabled` at the moment `makePaneOptionRows()` builds it MUST equal `options.isOverridden`.
- **reset-button-action**: Activating the reset button MUST call `options.reset()`.
- **reset-accessibility-identity**: The reset button MUST carry the accessibility identifier `document.options.reset` and the accessibility label `"Reset Editor Options to Defaults"`.
- **toggle-accessibility-identifiers**: The line-numbers, overview, and invisibles toggles' checkboxes MUST carry the accessibility identifiers `document.options.line-numbers`, `document.options.overview`, and `document.options.invisibles`, respectively.
- **rows-refresh-on-options-change**: Whenever `options` publishes a change (a pane-local edit, `reset()`, or a change to the corresponding app-wide setting) while a popover built from the most recent `makePaneOptionRows()` call is still open, the component MUST update that popover's three toggles' `isOn` and its reset button's `isEnabled` to the newly resolved values.
- **pane-override-isolated**: Two `DocumentEditorViewController` instances constructed with independent `EditorOptionsOverride`s MUST NOT let a change made through one instance's `makePaneOptionRows()` rows affect the other instance's resolved option values or `isOverridden` state.
- **reset-does-not-affect-other-panes-or-global**: Activating one instance's reset button MUST NOT change another instance's `isOverridden` state, resolved option values, or the underlying app-wide setting.

### Layout & Content Hosting

- **breadcrumb-above-content**: The component's view MUST arrange the breadcrumb directly above the hosted editor content in a vertical `NSStackView` with `spacing` `0` and `distribution` `.fill`.
- **breadcrumb-fixed-height**: The breadcrumb MUST be constrained to a fixed height of `24` points.
- **content-spans-container-width**: The breadcrumb and the hosted editor content MUST each have their leading and trailing edges pinned to the containing stack's leading and trailing edges.
- **root-view-initial-frame**: The controller's root view MUST be created with an initial frame of `520`×`424` points, with the stack pinned to all four of the root view's edges.
- **content-uses-themed-root**: The hosted SwiftUI content MUST be wrapped with `.themedRoot()` so it reads the app's theme palette and paints the theme's window background.
- **hosts-file-editor-view**: The component MUST host a `FileEditorView`, supplying it the current selection, `options`, `documentStore`, `saveScheduler`, `languageServices`, and an `openFile` closure that forwards its URL to `onOpenRequest`.

### Open-Request Routing

- **breadcrumb-selection-routes-out**: A URL chosen through the breadcrumb (a crumb, or a file from its popover) MUST be reported through `onOpenRequest`, not opened directly in this editor.
- **editor-open-request-routes-out**: A URL the hosted `FileEditorView` resolves and reports through its `openFile` closure MUST be reported through `onOpenRequest`, not opened directly in this editor.

## Appearance

- **Corner radius**: None set by this file.
- **Padding**: `0` stack spacing between the breadcrumb and the hosted content; no other padding is set directly by this file. The breadcrumb's own internal padding belongs to `BreadcrumbView` (out of scope; see its own recipe).
- **Font**: None set directly by this file. The gear-popover toggle rows' and reset button's fonts are the default `WindowOptionsToggle`/`NSButton` fonts (out of scope).
- **Background**: The hosted SwiftUI content paints the theme's `windowBackground`, via `.themedRoot()`'s default `paintsBackground: true` — a semantic theme token, not a literal color.
- **Foreground/Text**: The hosted SwiftUI content inherits the theme's `primaryText` color from `.themedRoot()`. The reset button and toggle titles use their controls' default colors.
- **Border**: None set by this file.
- **Shadow**: None set by this file.
- **Min/Max size**: None set by this file beyond the initial `520`×`424` root-view frame (see **root-view-initial-frame**); Auto Layout constraints, not a min/max size, govern the view thereafter.

