---
id: 4205c688-865a-4d74-890d-f803ee66fdcb
title: DocumentEditorViewController
domain: agentictoolkit://recipes/document-editor-view-controller
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: AppKit view controller for one editor pane, owning its file selection and
  breadcrumb, offering per-pane display-option overrides, and routing opens outward.
platforms:
- swift
- macos
tags:
- document
- editor
- pane
- view-controller
- appkit
depends-on:
- agentictoolkit://recipes/breadcrumb-view
- agentictoolkit://recipes/file-editor-view
related:
- agentictoolkit://recipes/breadcrumb-view
- agentictoolkit://recipes/file-editor-view
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

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

## Accessibility

- **Role/trait**: The container view is a plain `NSView` (via `NSHostingView` inside an `NSStackView`) with no explicit accessibility role override in this file. The four gear-popover rows carry the accessibility identifiers `document.options.line-numbers`, `document.options.overview`, `document.options.invisibles`, and `document.options.reset` (see **toggle-accessibility-identifiers**, **reset-accessibility-identity**). The breadcrumb's own accessibility identifiers and role are out of scope (see its own recipe).
- **Label requirements**: The reset button's accessibility label is set explicitly to `"Reset Editor Options to Defaults"`, distinct from its visible title `"Reset to Defaults"`. The three toggle rows' own accessibility labels are set by `WindowOptionsToggle` (out of scope for this recipe).
- **Announce state changes**: NEEDS REVIEW: Not implemented in source. Behavior undefined. When the displayed file changes — restored on construction, set through `fileURL`, or cleared through `clearDocument()` — the only signal this file produces is `onTitleChange`, consumed by the enclosing tab chrome (out of scope) to update its own title label. `show(_:persist:)` posts no accessibility notification of its own (e.g., a layout-changed or announcement notification) around the breadcrumb rebuild and editor-content swap, so whether a VoiceOver user tracking this pane is told the displayed file changed depends entirely on the enclosing chrome's own label update, which cannot be confirmed from this file alone. Settling it needs either a VoiceOver test pass on a `DocumentEditorViewController` pane after a `fileURL` change, or an explicit accessibility-notification addition to `show(_:persist:)`.
- **Minimum tap target**: Not applicable: this controller targets macOS pointer and trackpad input, not touch. No minimum width or height is set on the reset button or the toggle rows by this file, and macOS's HIG does not mandate a touch-target minimum for pointer-driven chrome the way iOS does for touch.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| devc-001 | file-url-key-constant | Read `DocumentEditorViewController.fileURLKey` | Equals `"fileURL"` |
| devc-002 | own-file-selection | Construct two controllers with the same `store`; set `fileURL` on the first only | The second controller's `fileURL` is unaffected |
| devc-003 | coder-init-unsupported | Call `init(coder:)` | Calls `fatalError` (process traps rather than returning) — verified by code inspection; a trapping call cannot be asserted in XCTest |
| devc-004 | restore-on-construction | `store` has `fileURLKey` set to a path that exists on disk; construct a controller | `fileURL` equals that path immediately after construction |
| devc-005 | missing-file-restore | `store` has `fileURLKey` set to a path with no file on disk; construct a controller | `fileURL` is `nil`; `store.paneStateValue(forKey: fileURLKey)` is now `nil`; `paneTitle` is `"Untitled"` |
| devc-006 | restore-omits-redundant-write | `store` has `fileURLKey` set to an existing file's path; construct a controller, spying on `setPaneStateValue` | No call to `setPaneStateValue(_:forKey: fileURLKey)` occurs during construction |
| devc-007 | file-url-reflects-selection | No selection set | `fileURL` is `nil` |
| devc-008 | set-file-url-updates-selection | Set `fileURL = URL(fileURLWithPath: "/tmp/a/Readme.md")` | The selection's node URL equals that path |
| devc-009 | set-file-url-persists | Set `fileURL = URL(fileURLWithPath: "/tmp/example/Readme.md")` | `store.paneStateValue(forKey: fileURLKey)` equals `"/tmp/example/Readme.md"` |
| devc-010 | set-file-url-updates-breadcrumb | Set `fileURL` to a non-nil URL | The breadcrumb's `fileURL` equals the same URL |
| devc-011 | file-url-title-change | Install a closure on `onTitleChange`; set `fileURL` | The closure is called |
| devc-012 | directory-detected-via-resource-value | Set `fileURL` to a URL for an existing directory | The selection's node has `isDirectory == true` |
| devc-013 | clear-document-preserves-pane | Set `fileURL`, then call `clearDocument()` | `fileURL` is `nil`; `store.paneStateValue(forKey: fileURLKey)` is `nil`; the pane/controller itself still exists |
| devc-014 | pane-title-is-filename | Set `fileURL = URL(fileURLWithPath: "/tmp/example/Readme.md")` | `paneTitle` equals `"Readme.md"` |
| devc-015 | pane-title-untitled-when-empty | Construct a controller with an empty store | `paneTitle` equals `"Untitled"` |
| devc-016 | title-change-callback-bridge | Assign a closure to `onPaneTitleChange` | Reading `onTitleChange` returns the same closure |
| devc-017 | options-rows-order | Call `makePaneOptionRows()` | Returns 4 views: 3 `WindowOptionsToggle`s ("Show line numbers", "Show overview", "Show invisibles") then one `NSButton` titled "Reset to Defaults", in that order |
| devc-018 | toggle-initial-state-resolved | `options.showOverview` is `false` at call time; call `makePaneOptionRows()` | The "Show overview" row's `isOn` is `false` |
| devc-019 | toggle-change-writes-override | Toggle the "Show line numbers" checkbox | `options.setShowLineNumbers(_:)` is called with the checkbox's new value |
| devc-020 | reset-button-label-and-style | Call `makePaneOptionRows()` | The fourth row's `title` is `"Reset to Defaults"` and `bezelStyle` is `.rounded` |
| devc-021 | reset-button-enabled-matches-override | `options.isOverridden` is `false`; call `makePaneOptionRows()` | The reset button's `isEnabled` is `false` |
| devc-022 | reset-button-action | Click the reset button | `options.reset()` is called |
| devc-023 | reset-accessibility-identity | Inspect the reset button | Accessibility identifier is `document.options.reset`; accessibility label is `"Reset Editor Options to Defaults"` |
| devc-024 | toggle-accessibility-identifiers | Inspect the three toggle rows' checkboxes | Identifiers are `document.options.line-numbers`, `document.options.overview`, `document.options.invisibles` respectively |
| devc-025 | rows-refresh-on-options-change | Build rows via `makePaneOptionRows()`, keeping references; then call `options.setShowOverview(true)` | The kept "Show overview" row's `isOn` becomes `true`; the kept reset button's `isEnabled` becomes `true` |
| devc-036 | rows-refresh-on-options-change | Build rows via `makePaneOptionRows()`, keeping references, with no pane-local override present; then change the app-wide `UserSettings.editorShowLineNumbers` value | The kept "Show line numbers" row's `isOn` updates to the new app-wide value |
| devc-037 | rows-refresh-on-options-change | Build rows via `makePaneOptionRows()`, then let the popover close so the kept row references become `nil`; then call `options.setShowOverview(true)` | No crash occurs; `refreshOptionRows()`'s optional-chained writes to the released rows are no-ops |
| devc-026 | pane-override-isolated | Two controllers, each with its own `EditorOptionsOverride`; toggle "Show line numbers" on the first via its row | The first's `options.showLineNumbers` flips and `isOverridden` becomes `true`; the second's `options.showLineNumbers` and `isOverridden` are unchanged |
| devc-027 | reset-does-not-affect-other-panes-or-global | Override "Show line numbers" on both of two controllers, then click the first's reset button | The first's `isOverridden` becomes `false`; the second's `isOverridden` stays `true`; the app-wide `UserSettings.editorShowLineNumbers` value is unchanged |
| devc-028 | breadcrumb-above-content | Load the controller's view | The root stack's arranged subviews are `[breadcrumb, hostingView]`, `orientation == .vertical`, `spacing == 0` |
| devc-029 | breadcrumb-fixed-height | Load the controller's view | The breadcrumb's height constraint constant is `24` |
| devc-030 | content-spans-container-width | Load the controller's view | Both the breadcrumb's and the hosting view's leading/trailing constraints pin to the stack's leading/trailing anchors |
| devc-031 | root-view-initial-frame | Call `loadView()` | The returned root view's initial frame is `(0, 0, 520, 424)`; the stack's top/bottom/leading/trailing constraints pin to the root view |
| devc-032 | content-uses-themed-root | Inspect the hosted `NSHostingView`'s root view modifier chain | `.themedRoot()` is applied — verified by code inspection; a modifier chain cannot be introspected in XCTest |
| devc-033 | hosts-file-editor-view | Load the controller's view with a non-nil selection | The hosted content is a `FileEditorView` receiving that selection, `options`, `documentStore`, `saveScheduler`, and `languageServices` |
| devc-034 | breadcrumb-selection-routes-out | Install a closure on `onOpenRequest`; invoke the breadcrumb's `onSelect` with a URL | `onOpenRequest` is called with that URL; `fileURL` is unchanged |
| devc-035 | editor-open-request-routes-out | Install a closure on `onOpenRequest`; invoke the hosted content's `openFile` closure with a URL | `onOpenRequest` is called with that URL |
| devc-038 | construction-title-change | Install a closure on `onTitleChange`; construct a controller whose `store` has `fileURLKey` set to an existing file's path | The closure is called during construction |

## Edge Cases

- **Null/empty input**: `fileURL` set to `nil` clears the selection and the breadcrumb (see **set-file-url-updates-selection**, **set-file-url-updates-breadcrumb**). `rootURL` and `store` are required, non-optional values supplied at initialization, so neither has a null case to handle here.
- **Boundary — a stored path that now names a directory**: `restoreStoredDocument()` checks only `FileManager.default.fileExists(atPath:)`, which returns `true` for a directory as well as a file. A stored path whose file has been replaced by a same-named directory therefore restores: `fileURL` becomes that directory's URL, `paneTitle` becomes the directory's last path component, and the breadcrumb shows it — while the hosted `FileEditorView` shows no openable content for it, because its own `openableNode` filter excludes directories (see **directory-detected-via-resource-value**). The pane title names a directory that is not actually open in the editor; this is what the source does, not an unresolved question.
- **Concurrent access**: The class is declared `@MainActor`, so every mutation of `fileURL`, the selection, and the gear-popover row references happens on the main actor; `options`'s debounced persistence (`DispatchQueue.main.asyncAfter`) is also scheduled back onto the main actor. No interleaving of two `show(_:persist:)` calls, or of a `show` and a gear-row refresh, is possible.
- **Error states**: `isDirectory(_:)` queries `url.resourceValues(forKeys: [.isDirectoryKey])` with `try?`, silently treating any failure (a permission error, a race where the file disappears mid-query) as "not a directory" (`false`) rather than surfacing an error. `restoreStoredDocument()` treats a missing file the same way — silently clearing the stored value rather than reporting an error to the caller (see **missing-file-restore**). Both are documented here as the source implements them, not idealized with an error UI the source does not have.
- **Offline or disconnected state**: Not applicable. This file performs no networking; its only I/O is local-disk existence and resource-value checks and reads/writes through the caller-supplied `PaneStateStore`.

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

## Deep Linking

Not applicable: `DocumentEditorViewController` has no URL scheme, route, or deep-link entry point in source. It displays a `fileURL` already resolved and supplied by its owner or restored from `store`, and reports URLs it cannot open itself through `onOpenRequest` rather than navigating a URL scheme.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal string) | "Untitled" | `paneTitle` when no file is displayed. |
| (none — literal string) | "Show line numbers" | First gear-popover toggle's title. |
| (none — literal string) | "Show overview" | Second gear-popover toggle's title. |
| (none — literal string) | "Show invisibles" | Third gear-popover toggle's title. |
| (none — literal string) | "Reset to Defaults" | Reset button's visible title. |
| (none — literal string) | "Reset Editor Options to Defaults" | Reset button's accessibility label. |

NEEDS REVIEW: Not implemented in source. Behavior undefined. No localization key or `String(localized:)`/`.strings`-catalog mechanism exists for any user-facing string in this file — every string above is a hardcoded English literal. Resolution requires the app team deciding whether this chrome should be localized, and updating this file accordingly if so.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: every method in this file (`show`, `clearDocument`, `refreshOptionRows`) mutates views immediately with no `NSAnimationContext`, layer animation, or transition, so there is no motion for this setting to reduce. |
| Increase Contrast | Not observed in this file: the hosted content's background and foreground colors are resolved through the theme system via `.themedRoot()`; any contrast adaptation belongs to that system, out of this ingredient's scope. |
| Differentiate Without Color | Not applicable: no state in this file is conveyed by color alone. The reset button's enabled/disabled state uses AppKit's own standard button-disabled rendering (not a custom color-only cue), and each toggle's checked state is conveyed by its checkbox glyph, not by color. |

## Feature Flags

Not applicable: no feature-flag or remote-config lookup of any kind appears anywhere in this file.

## Analytics

Not applicable: no analytics event is emitted anywhere in this file.

## Privacy

- **Data collected**: This file introduces no new data collection beyond the file path the user is already viewing in this window. No personal or sensitive data is read or written by this file itself.
- **Storage**: Local only, through the caller-supplied `PaneStateStore`, under the key `fileURLKey`. The concrete store's durability is opaque to this file: `EphemeralPaneStateStore` (used in tests, and for a container with nothing to persist) forgets its values as soon as it is deallocated, while a project window's own store persists `pane_state` beyond app restarts. This file specifies only that it writes/reads that one key; the durability guarantee is the store's, not this file's.
- **Transmission**: None. No network call appears anywhere in this file.
- **Retention**: Tied to the given `store`'s own retention policy; this file's only retention-relevant action is writing `nil` for `fileURLKey` when the document is cleared or the stored file no longer exists (see **clear-document-preserves-pane**, **missing-file-restore**).

## Logging

Not applicable: no logging call (`Logger`, `os_log`, or otherwise) appears anywhere in this file.

## Platform Notes

- **SwiftUI**: The hosted content is already SwiftUI (a private wrapper struct forwarding to `FileEditorView`; see the AppKit / UIKit note below); a fully SwiftUI rebuild of the outer shell would replace the `NSViewController`/`NSStackView` wrapper with a `VStack(spacing: 0)` containing a SwiftUI breadcrumb view (see its own recipe) constrained to a `24`pt frame height and the `FileEditorView` filling the remaining space, driven by an `@Observable` pane view model exposing `fileURL`, `paneTitle`, and the resolved option values in place of `EditorOptionsOverride`'s `ObservableObject`/Combine publisher, and applying `.themedRoot()` once at that `VStack`'s root exactly as this file does today.
- **Compose**: Model the pane as a `Column` with a fixed-height (`24.dp`-equivalent) breadcrumb `Row` and a `Box(Modifier.weight(1f))` for the editor content. Hold the per-pane option overrides in a small `ViewModel`-scoped `StateFlow` per option, each resolving to a `Boolean?` (absent, meaning "follow the app-wide `DataStore` preference") exactly as `EditorOptionsOverride` does, and observe the shared `DataStore` flow the same way `EditorOptionsOverride.observeGlobals()` observes `UserSettings`, republishing the resolved values so a change in either scope updates any visible options sheet.
- **React/Web**: Render a flex column: a fixed-height breadcrumb bar, then a `flex: 1; overflow: auto` editor container. Hold `fileURL` and the three option overrides in per-instance React state (not global state), persisting them to a per-pane key in `sessionStorage`/`localStorage` (mirroring the pane-scoped `PaneStateStore` key), and resolve each option as `paneOverride ?? globalSetting` on every render rather than snapshotting it once, so a later change to the global setting is still picked up by a pane that has not overridden that option.
- **AppKit / UIKit**: Source: `DocumentEditorViewController.swift` (`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/DocumentPane/`), AppKit-only — `NSViewController`, `NSHostingView`, `NSStackView`, `NSButton`, and Combine for the options observer, hosting a private `DocumentEditorPaneView` SwiftUI struct that forwards to `FileEditorView`; nothing in this file targets UIKit/iOS. A UIKit port would replace the gear-triggered popover (owned by the pane chrome, out of scope) with an options screen presented from a toolbar item, since iOS has no macOS-style gear-popover convention, and would need to post an explicit `UIAccessibility.post(notification: .screenChanged, argument:)` (or similar) when the displayed file changes, since whether the retitle-only signal this file provides (`onTitleChange`) is itself already announced on macOS is the open question noted under Announce state changes in Accessibility.
- **WinUI 3**: Rebuild the shell as a `UserControl` containing a two-row `Grid`: a fixed-height row (`GridLength` matching the `24`px breadcrumb height) hosting a `BreadcrumbBar`-based analogue (see the Breadcrumb View recipe) and a content row hosting the editor. Persist the open file's path per pane through an `ApplicationData.Current.LocalSettings` composite key mirroring `PaneStateStore`'s per-pane prefix, restoring it in the control's `Loaded` handler and clearing that key when `StorageFile.GetFileFromPathAsync` throws `FileNotFoundException` (mirroring **missing-file-restore**). Model the three toggles and the reset button as a `Flyout` (or `MenuFlyoutSubItem`) opened from a gear `AppBarButton`, using three `ToggleSwitch` controls bound to a small object that resolves each option as "pane override, else roaming `ApplicationData` setting" exactly as `EditorOptionsOverride` does, and refresh the flyout's `ToggleSwitch.IsOn` and the reset button's `IsEnabled` from that object's change event the same way `refreshOptionRows()` does. Route a URL this control cannot open in place through a routed or bubbled event rather than a closure, mirroring `onOpenRequest`, since WinUI favors events over stored closures for cross-control communication.

## Design Decisions

**Decision**: `show(_:persist:)` determines whether a URL is a directory by asking `url.resourceValues(forKeys: [.isDirectoryKey])` rather than assuming every URL it is given names a file.
**Rationale**: Every caller hands over a bare URL — a restored path, a breadcrumb choice, a go-to-definition target, the file tree's own open request — and a directory is among the things they can legitimately name; asserting it was always a file previously let `FileEditorView.openableNode` read a directory off disk.
**Approved**: pending

**Decision**: The gear popover's row references (`lineNumbersRow`, `overviewRow`, `invisiblesRow`, `resetRow`) are held `weak` and individually, not as a strong array.
**Rationale**: The options dialog owns its views and takes them with it when it closes; holding them weakly lets the references go `nil` on their own rather than keeping a dismissed dialog's checkboxes alive to be written to by a later `refreshOptionRows()` call.
**Approved**: pending

**Decision**: Restoring a stored file during initialization calls `show(url, persist: false)`, while `fileURL`'s setter and `clearDocument()` call `show(_, persist: true)`.
**Rationale**: A value just read from the store does not need to be written straight back to it; only a change made after construction needs to be persisted.
**Approved**: pending

**Decision**: `EditorOptionsOverride` resolves each of its three options independently, on every read (`stored.showLineNumbers ?? UserSettings.editorShowLineNumbers.value`), rather than this controller snapshotting the resolved values once.
**Rationale**: An editor pane must keep following the app-wide setting for any option it has not itself overridden, so that overriding "line numbers" in one pane never silently pins "overview" or "invisibles" in that same pane, and so a later app-wide change still reaches a pane that has not overridden that option.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [state-recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | partial | Reliability |

The `screen-reader-support` status is partial: the reset button's and each toggle's accessibility labels and identifiers are set explicitly (see Accessibility, **toggle-accessibility-identifiers**, **reset-accessibility-identity**), but whether a file change is itself announced to a screen reader is the open question flagged under Accessibility (Announce state changes). The `no-hardcoded-strings` status is failed because six user-facing strings in this file are hardcoded English literals with no localization mechanism (see Localization). The `state-recovery` status is partial because this file specifies only that it reads and writes one key on a caller-supplied `PaneStateStore`; the actual durability guarantee belongs to whichever concrete store the caller supplies (see Privacy, Storage).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Claude | Initial creation from source code |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed three action-style requirements to subject form and split the title-change requirement into setter and restore variants; dropped bare trailing Edge Case MUST tags; reworded the AppKit title-announcement note to cite the open accessibility question instead of asserting it; moved the internal `references` URL to `related` and added `depends-on`/`related` entries for the hosted child recipes; trimmed `tags` to the 1-5 limit; bolded the Design Decisions labels; corrected the Compliance table to cite real catalog checks and changed its `needs-review` status to `partial`; removed leftover template scaffold text from Accessibility Options; unified the hosted-content naming around `FileEditorView`, moving the private wrapper's name into the AppKit Platform Note; narrowed devc-012 to the selection node and marked devc-003/devc-032 as verified by code inspection; added test vectors for an app-wide options change and a dismissed popover; and split `clearDocument()` into a Methods list while adding `paneTitle`/`onPaneTitleChange` to Configuration |
