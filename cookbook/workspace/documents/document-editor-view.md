---
id: 4205c688-865a-4d74-890d-f803ee66fdcb
title: Document Editor
domain: agentictoolkit://cookbook/workspace/documents/document-editor-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A component for one editor pane, owning its file selection and breadcrumb,
  offering per-pane display-option overrides, and routing opens outward.
platforms:
- swift
- macos
tags:
- document
- editor
- pane
depends-on:
- agentictoolkit://cookbook/workspace/documents/breadcrumb-view
- agentictoolkit://cookbook/workspace/files/file-editor-view
related:
- agentictoolkit://cookbook/workspace/documents/breadcrumb-view
- agentictoolkit://cookbook/workspace/files/file-editor-view
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

# Document Editor

## Overview

This component is one editor inside one pane of one tab. It hosts a breadcrumb above a file editor (each out of this recipe's scope; see their own recipes) and holds its own file-browser selection rather than sharing the browser's, so two editors open side by side in the same window can each show a different file. It restores the last file it showed from a caller-supplied pane-state store, exposes a per-pane override of the editor's three display toggles (line numbers, overview, invisibles) through a pane-options-providing role, exposes its title through a pane-title-providing role, and routes any file it cannot open itself — a breadcrumb choice, a go-to-definition target — outward through an open-request callback rather than opening it in place, because the file browser's own selection is the one place that decides what is open across the whole window.

## Behavioral Requirements

### Identity & Construction

- **file-url-key-constant**: The storage key used to persist the displayed file's URL MUST equal the literal string `"fileURL"`.
- **own-file-selection**: The component MUST hold its own file-browser selection state, distinct from any other instance of this component's selection, so that two editors can display two different files at once.
- **no-decoded-initialization**: The component MUST NOT support construction from a serialized/decoded representation (such as a saved interface file), and MUST fail fast if such construction is attempted.
- **restore-on-construction**: During initialization, the component MUST read the stored file URL from the pane-state store and, when a value is present and its file exists on disk, MUST display that file.
- **missing-file-restore**: When the stored path's file does not exist on disk, the component MUST clear the stored value and leave the displayed file unset, rather than displaying or erroring on a missing file.
- **restore-omits-redundant-write**: Restoring a stored file during initialization MUST NOT write that same value back to the store; only a subsequent call that changes the displayed file MUST write to the store.
- **construction-title-change**: Restoring a stored file during initialization MUST also invoke the title-change callback afterward, the same as any other call that changes the displayed file.

### Displaying and Changing the File

- **file-url-reflects-selection**: The displayed-file property MUST return the URL of the currently selected file-browser node, or none when no node is selected.
- **set-file-url-updates-selection**: Setting the displayed file to a value MUST set the selection to a node for that URL; clearing it MUST clear the selection.
- **set-file-url-persists**: Setting the displayed file MUST write the new value — the URL's path, or none — to the pane-state store under the file-URL storage key.
- **set-file-url-updates-breadcrumb**: Setting the displayed file MUST set the breadcrumb's displayed file to the same value.
- **file-url-title-change**: Setting the displayed file MUST invoke the title-change callback afterward.
- **directory-detected-via-resource-value**: The component MUST determine whether a URL being shown is a directory by querying the URL's own directory-resource metadata, defaulting to "not a directory" when that query fails, rather than assuming the URL is a file because of how it was obtained.
- **clear-document-preserves-pane**: Clearing the document MUST unset the displayed file and persist that clearing, and MUST NOT remove the pane or otherwise affect anything beyond the displayed file.

### Pane Title

- **pane-title-is-filename**: The pane title MUST equal the displayed file's last path component when a file is displayed.
- **pane-title-untitled-when-empty**: The pane title MUST equal the literal string `"Untitled"` when no file is displayed.
- **title-change-callback-bridge**: The pane-title-change callback's getter and setter MUST read and write the same underlying callback as the title-change callback.

### Editor Options Popover

- **options-rows-order**: Building the pane's option rows MUST return exactly four views/rows, in order: the "Show line numbers" toggle, the "Show overview" toggle, the "Show invisibles" toggle, then the reset button.
- **toggle-initial-state-resolved**: Each toggle's on/off state at the moment the option rows are built MUST equal the corresponding resolved display-option value (show line numbers, show overview, show invisibles).
- **toggle-change-writes-override**: Changing a toggle's value MUST write the new value to the matching display-option override (show line numbers, show overview, or show invisibles).
- **reset-button-label-and-style**: The fourth row MUST be a button titled `"Reset to Defaults"` with a rounded button style.
- **reset-button-enabled-matches-override**: The reset button's enabled state at the moment the option rows are built MUST equal whether any display option is currently overridden in this pane.
- **reset-button-action**: Activating the reset button MUST reset every display-option override in this pane.
- **reset-accessibility-identity**: The reset button MUST carry the accessibility identifier `document.options.reset` and the accessibility label `"Reset Editor Options to Defaults"`.
- **toggle-accessibility-identifiers**: The line-numbers, overview, and invisibles toggles' checkboxes MUST carry the accessibility identifiers `document.options.line-numbers`, `document.options.overview`, and `document.options.invisibles`, respectively.
- **rows-refresh-on-options-change**: Whenever a display-option value changes (a pane-local edit, a reset, or a change to the corresponding app-wide setting) while a popover built from the most recently built option rows is still open, the component MUST update that popover's three toggles' on/off state and its reset button's enabled state to the newly resolved values.
- **pane-override-isolated**: Two instances of this component constructed with independent per-pane display-option overrides MUST NOT let a change made through one instance's option rows affect the other instance's resolved option values or overridden state.
- **reset-does-not-affect-other-panes-or-global**: Activating one instance's reset button MUST NOT change another instance's overridden state, resolved option values, or the underlying app-wide setting.

### Layout & Content Hosting

- **breadcrumb-above-content**: The component's view MUST arrange the breadcrumb directly above the hosted editor content in a vertical stack with 0 spacing between them and a fill distribution.
- **breadcrumb-fixed-height**: The breadcrumb MUST be constrained to a fixed height of `24` points.
- **content-spans-container-width**: The breadcrumb and the hosted editor content MUST each have their leading and trailing edges pinned to the containing stack's leading and trailing edges.
- **root-view-initial-frame**: The component's root view MUST be created with an initial size of `520`×`424` points, with the stack pinned to all four of the root view's edges.
- **content-uses-themed-root**: The hosted content MUST be wrapped with the shared theming root so it reads the app's theme palette and paints the theme's window background.
- **hosts-file-editor-view**: The component MUST host a file editor, supplying it the current selection, the display-option overrides, the document store, the save scheduler, the language services, and an open-file callback that forwards its URL to the open-request callback.

### Open-Request Routing

- **breadcrumb-selection-routes-out**: A URL chosen through the breadcrumb (a crumb, or a file from its popover) MUST be reported through the open-request callback, not opened directly in this editor.
- **editor-open-request-routes-out**: A URL the hosted file editor resolves and reports through its open-file callback MUST be reported through the open-request callback, not opened directly in this editor.

## Appearance

- **Corner radius**: None set by this file.
- **Padding**: `0` stack spacing between the breadcrumb and the hosted content; no other padding is set directly by this file. The breadcrumb's own internal padding belongs to the breadcrumb component (out of scope; see its own recipe).
- **Font**: None set directly by this file. The gear-popover toggle rows' and reset button's fonts are their controls' own default fonts (out of scope).
- **Background**: The hosted content paints the theme's window-background role, via the shared theming root's default background-painting behavior — a semantic theme token, not a literal color.
- **Foreground/Text**: The hosted content inherits the theme's primary-text color role from the shared theming root. The reset button and toggle titles use their controls' default colors.
- **Border**: None set by this file.
- **Shadow**: None set by this file.
- **Min/Max size**: None set by this file beyond the initial `520`×`424` root-view frame (see **root-view-initial-frame**); layout constraints, not a min/max size, govern the view thereafter.

## States

| State | Appearance change |
|-------|------------------|
| Default | Editor shows the displayed file, or an empty editor state (delegated to the file editor, out of scope) when no file is displayed |
| Pressed | Not applicable: this component is a container. The reset button's and toggles' own pressed appearance is drawn by the platform and their own controls, out of scope for this recipe. |
| Disabled | Not applicable to the container itself; the reset button is individually enabled or disabled (see **reset-button-enabled-matches-override**) — not the whole editor. |
| Focused | Not applicable: this file sets no custom focus-ring drawing; keyboard focus on its buttons and toggles is the platform's own default rendering. |
| Loading | Not applicable: every method in this file is synchronous. Any asynchronous loading of file content belongs to the file editor / document store, out of scope. |
| File open | Breadcrumb shows the path from the project root to the displayed file; the pane title is the file's last path component. |
| No file (no file displayed) | Breadcrumb is empty; the pane title is `"Untitled"`. |
| An option overridden in this pane | The gear popover's reset button is enabled; the overridden toggle(s) reflect the pane-local value rather than the app-wide setting. |
| No option overridden in this pane | The reset button is disabled; every toggle reflects the app-wide setting. |

## Accessibility

- **Role/trait**: The container view is a plain view with no explicit accessibility role override in this file. The four gear-popover rows carry the accessibility identifiers `document.options.line-numbers`, `document.options.overview`, `document.options.invisibles`, and `document.options.reset` (see **toggle-accessibility-identifiers**, **reset-accessibility-identity**). The breadcrumb's own accessibility identifiers and role are out of scope (see its own recipe).
- **Label requirements**: The reset button's accessibility label is set explicitly to `"Reset Editor Options to Defaults"`, distinct from its visible title `"Reset to Defaults"`. The three toggle rows' own accessibility labels are set by their own controls (out of scope for this recipe).
- **Announce state changes**: When the displayed file changes — restored on construction, set through the displayed-file property, or cleared through clearing the document — this file posts no accessibility notification of its own (e.g., a layout-changed or announcement notification) around the breadcrumb rebuild and editor-content swap. The only signal it produces is the title-change callback, consumed by the enclosing tab chrome (out of scope) to update its own title label; whether a screen-reader user tracking this pane is told the displayed file changed depends entirely on that enclosing chrome's own label update.
- **Minimum tap target**: Not applicable: this component targets pointer and trackpad input, not touch. No minimum width or height is set on the reset button or the toggle rows by this file, and the source platform's design guidance does not mandate a touch-target minimum for pointer-driven chrome the way a touch platform does for touch.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| devc-001 | file-url-key-constant | Read the file-URL storage key constant | Equals `"fileURL"` |
| devc-002 | own-file-selection | Construct two component instances with the same pane-state store; set the displayed file on the first only | The second instance's displayed file is unaffected |
| devc-003 | no-decoded-initialization | Attempt construction from a decoded/serialized representation | Fails fast (the process traps rather than returning) — verified by code inspection; a trapping call cannot be asserted by an automated test |
| devc-004 | restore-on-construction | The pane-state store has the file-URL key set to a path that exists on disk; construct the component | The displayed file equals that path immediately after construction |
| devc-005 | missing-file-restore | The pane-state store has the file-URL key set to a path with no file on disk; construct the component | The displayed file is unset; the stored value is now cleared; the pane title is `"Untitled"` |
| devc-006 | restore-omits-redundant-write | The pane-state store has the file-URL key set to an existing file's path; construct the component, spying on the store's write operation | No write to the store occurs during construction |
| devc-007 | file-url-reflects-selection | No selection set | The displayed file is unset |
| devc-008 | set-file-url-updates-selection | Set the displayed file to /tmp/a/Readme.md | The selection's node URL equals that path |
| devc-009 | set-file-url-persists | Set the displayed file to /tmp/example/Readme.md | The stored value equals `"/tmp/example/Readme.md"` |
| devc-010 | set-file-url-updates-breadcrumb | Set the displayed file to a value | The breadcrumb's displayed file equals the same URL |
| devc-011 | file-url-title-change | Install a callback on the title-change callback; set the displayed file | The callback is called |
| devc-012 | directory-detected-via-resource-value | Set the displayed file to a URL for an existing directory | The selection's node is marked as a directory |
| devc-013 | clear-document-preserves-pane | Set the displayed file, then clear the document | The displayed file is unset; the stored value is cleared; the pane/component itself still exists |
| devc-014 | pane-title-is-filename | Set the displayed file to /tmp/example/Readme.md | The pane title equals `"Readme.md"` |
| devc-015 | pane-title-untitled-when-empty | Construct the component with an empty pane-state store | The pane title equals `"Untitled"` |
| devc-016 | title-change-callback-bridge | Assign a callback to the pane-title-change callback | Reading the title-change callback returns the same callback |
| devc-017 | options-rows-order | Build the pane's option rows | Returns 4 views/rows: 3 toggles ("Show line numbers", "Show overview", "Show invisibles") then one button titled "Reset to Defaults", in that order |
| devc-018 | toggle-initial-state-resolved | The resolved "show overview" value is false at call time; build the option rows | The "Show overview" row's on/off state is false |
| devc-019 | toggle-change-writes-override | Toggle the "Show line numbers" checkbox | The "show line numbers" override is set to the checkbox's new value |
| devc-020 | reset-button-label-and-style | Build the option rows | The fourth row's title is `"Reset to Defaults"` and its style is rounded |
| devc-021 | reset-button-enabled-matches-override | No display option is overridden; build the option rows | The reset button's enabled state is false |
| devc-022 | reset-button-action | Click the reset button | Every display-option override in this pane is reset |
| devc-023 | reset-accessibility-identity | Inspect the reset button | Accessibility identifier is `document.options.reset`; accessibility label is `"Reset Editor Options to Defaults"` |
| devc-024 | toggle-accessibility-identifiers | Inspect the three toggle rows' checkboxes | Identifiers are `document.options.line-numbers`, `document.options.overview`, `document.options.invisibles` respectively |
| devc-025 | rows-refresh-on-options-change | Build the option rows, keeping references; then set the "show overview" override to true | The kept "Show overview" row's on/off state becomes true; the kept reset button's enabled state becomes true |
| devc-036 | rows-refresh-on-options-change | Build the option rows, keeping references, with no pane-local override present; then change the app-wide "show line numbers" setting | The kept "Show line numbers" row's on/off state updates to the new app-wide value |
| devc-037 | rows-refresh-on-options-change | Build the option rows, then let the popover close so the kept row references become unset; then set the "show overview" override to true | No crash occurs; the refresh operation's writes to the released rows are no-ops |
| devc-026 | pane-override-isolated | Two component instances, each with its own independent display-option overrides; toggle "Show line numbers" on the first via its row | The first's resolved "show line numbers" value flips and its overridden state becomes true; the second's resolved value and overridden state are unchanged |
| devc-027 | reset-does-not-affect-other-panes-or-global | Override "Show line numbers" on both of two instances, then click the first's reset button | The first's overridden state becomes false; the second's stays true; the app-wide "show line numbers" setting is unchanged |
| devc-028 | breadcrumb-above-content | Load the component's view | The root stack's child views are, in order, the breadcrumb then the hosted content; its orientation is vertical; its spacing is 0 |
| devc-029 | breadcrumb-fixed-height | Load the component's view | The breadcrumb's height constraint constant is `24` |
| devc-030 | content-spans-container-width | Load the component's view | Both the breadcrumb's and the hosted content's leading/trailing edges pin to the stack's leading/trailing edges |
| devc-031 | root-view-initial-frame | Load the component's view | The returned root view's initial position and size is `(0, 0, 520, 424)`; the stack's top/bottom/leading/trailing edges pin to the root view's edges |
| devc-032 | content-uses-themed-root | Inspect the hosted content's root-view wrapping | The shared theming root is applied — verified by code inspection; this wrapping cannot be introspected by an automated test |
| devc-033 | hosts-file-editor-view | Load the component's view with a selection present | The hosted content is a file editor receiving that selection, the display-option overrides, the document store, the save scheduler, and the language services |
| devc-034 | breadcrumb-selection-routes-out | Install a callback on the open-request callback; invoke the breadcrumb's selection callback with a URL | The open-request callback is called with that URL; the displayed file is unchanged |
| devc-035 | editor-open-request-routes-out | Install a callback on the open-request callback; invoke the hosted content's open-file callback with a URL | The open-request callback is called with that URL |
| devc-038 | construction-title-change | Install a callback on the title-change callback; construct the component whose pane-state store has the file-URL key set to an existing file's path | The callback is called during construction |

## Edge Cases

- **Null/empty input**: The displayed file being unset clears the selection and the breadcrumb (see **set-file-url-updates-selection**, **set-file-url-updates-breadcrumb**). The project root and the pane-state store are required values supplied at initialization, so neither has a null case to handle here.
- **Boundary — a stored path that now names a directory**: Restoring the stored document checks only whether a file-system entry exists at that path, which is true for a directory as well as a file. A stored path whose file has been replaced by a same-named directory therefore restores: the displayed file becomes that directory's URL, the pane title becomes the directory's last path component, and the breadcrumb shows it — while the hosted file editor shows no openable content for it, because its own content filter excludes directories (see **directory-detected-via-resource-value**). The pane title names a directory that is not actually open in the editor; this is what the source does, not an unresolved question.
- **Concurrent access**: This component confines every mutation of the displayed file, the selection, and the gear-popover row references to a single execution context, enforced by the platform's concurrency checker; the display-option overrides' debounced persistence is also scheduled back onto that same context. No interleaving of two file-display operations, or of a file-display operation and a gear-row refresh, is possible.
- **Error states**: The directory check silently treats any failure to query a URL's directory metadata (a permission error, a race where the file disappears mid-query) as "not a directory" rather than surfacing an error. Restoring the stored document treats a missing file the same way — silently clearing the stored value rather than reporting an error to the caller (see **missing-file-restore**). Both are documented here as the source implements them, not idealized with an error UI the source does not have.
- **Offline or disconnected state**: Not applicable. This file performs no networking; its only I/O is local-disk existence and resource-value checks and reads/writes through the caller-supplied pane-state store.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Pane-state store | pane-state store (required at init) | required at init | Where the displayed file's path is read and written under the file-URL key. An ephemeral store forgets its values when deallocated; a project window supplies a store backed by durable local storage instead (see Privacy, Storage). |
| Document store | document store (required at init) | required at init | Passed through unchanged to the hosted file editor (out of scope). |
| Save scheduler | save scheduler (required at init) | required at init | Passed through unchanged to the hosted file editor (out of scope). |
| Language services | optional language services (required at init, may be absent) | required at init (may be absent) | Passed through unchanged to the hosted file editor (out of scope). |
| Project root | URL (required at init) | required at init | The project root the breadcrumb computes its crumbs relative to; handed to the breadcrumb at construction and never changed afterward. |
| Display-option overrides | per-pane override (created at init from the pane-state store) | created at init from the pane-state store | This pane's independent override of the three editor display toggles; publicly readable, not settable. |
| Displayed file | URL (optional) | none, or restored from the pane-state store at init | The file currently displayed. Setting it updates the selection, the breadcrumb, and the store, and fires the title-change callback. |
| Title-change callback | optional callback | none | Called after every change to the displayed file. |
| Pane title | string (read-only) | the displayed file's last path component, or `"Untitled"` | Read-only; see **pane-title-is-filename**, **pane-title-untitled-when-empty**. |
| Pane-title-change callback | optional callback | none | Getter/setter bridge onto the title-change callback; see **title-change-callback-bridge**. |
| Open-request callback | optional callback receiving a URL | none | Called with a URL the breadcrumb or the hosted editor resolved but did not open in place. |

### Methods

| Method | Description |
|--------|-------------|
| Clear document | Unsets the displayed file and persists that, without removing the pane; see **clear-document-preserves-pane**. |

## Deep Linking

Not applicable: this component has no URL scheme, route, or deep-link entry point in source. It displays a file already resolved and supplied by its owner or restored from the pane-state store, and reports URLs it cannot open itself through the open-request callback rather than navigating a URL scheme.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal string) | "Untitled" | Pane title when no file is displayed. |
| (none — literal string) | "Show line numbers" | First gear-popover toggle's title. |
| (none — literal string) | "Show overview" | Second gear-popover toggle's title. |
| (none — literal string) | "Show invisibles" | Third gear-popover toggle's title. |
| (none — literal string) | "Reset to Defaults" | Reset button's visible title. |
| (none — literal string) | "Reset Editor Options to Defaults" | Reset button's accessibility label. |

No localization key or platform localization mechanism exists for any user-facing string in this file — every string above is a hardcoded English literal.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: every operation in this file mutates views immediately with no animation or transition, so there is no motion for this setting to reduce. |
| Increase Contrast | Not observed in this file: the hosted content's background and foreground colors are resolved through the theme system via the shared theming root; any contrast adaptation belongs to that system, out of this ingredient's scope. |
| Differentiate Without Color | Not applicable: no state in this file is conveyed by color alone. The reset button's enabled/disabled state uses the platform's own standard button-disabled rendering (not a custom color-only cue), and each toggle's checked state is conveyed by its checkbox glyph, not by color. |

## Feature Flags

Not applicable: no feature-flag or remote-config lookup of any kind appears anywhere in this file.

## Analytics

Not applicable: no analytics event is emitted anywhere in this file.

## Privacy

- **Data collected**: This file introduces no new data collection beyond the file path the user is already viewing in this window. No personal or sensitive data is read or written by this file itself.
- **Storage**: Local only, through the caller-supplied pane-state store, under the file-URL key. The concrete store's durability is opaque to this file: an ephemeral store (used in tests, and for a container with nothing to persist) forgets its values as soon as it is deallocated, while a project window's own store persists `pane_state` beyond app restarts. This file specifies only that it writes/reads that one key; the durability guarantee is the store's, not this file's.
- **Transmission**: None. No network call appears anywhere in this file.
- **Retention**: Tied to the given store's own retention policy; this file's only retention-relevant action is writing none for the file-URL key when the document is cleared or the stored file no longer exists (see **clear-document-preserves-pane**, **missing-file-restore**).

## Logging

Not applicable: no logging call appears anywhere in this file.

## Platform Notes

- **SwiftUI**: The hosted content is already SwiftUI (a private wrapper struct forwarding to `FileEditorView`; see the AppKit / UIKit note below); a fully SwiftUI rebuild of the outer shell would replace the `NSViewController`/`NSStackView` wrapper with a `VStack(spacing: 0)` containing a SwiftUI breadcrumb view (see its own recipe) constrained to a `24`pt frame height and the `FileEditorView` filling the remaining space, driven by an `@Observable` pane view model exposing `fileURL`, `paneTitle`, and the resolved option values in place of `EditorOptionsOverride`'s `ObservableObject`/Combine publisher, and applying `.themedRoot()` once at that `VStack`'s root exactly as this file does today.
- **Compose**: Model the pane as a `Column` with a fixed-height (`24.dp`-equivalent) breadcrumb `Row` and a `Box(Modifier.weight(1f))` for the editor content. Hold the per-pane option overrides in a small `ViewModel`-scoped `StateFlow` per option, each resolving to a `Boolean?` (absent, meaning "follow the app-wide `DataStore` preference") exactly as `EditorOptionsOverride` does, and observe the shared `DataStore` flow the same way `EditorOptionsOverride.observeGlobals()` observes `UserSettings`, republishing the resolved values so a change in either scope updates any visible options sheet.
- **React/Web**: Render a flex column: a fixed-height breadcrumb bar, then a `flex: 1; overflow: auto` editor container. Hold `fileURL` and the three option overrides in per-instance React state (not global state), persisting them to a per-pane key in `sessionStorage`/`localStorage` (mirroring the pane-scoped `PaneStateStore` key), and resolve each option as `paneOverride ?? globalSetting` on every render rather than snapshotting it once, so a later change to the global setting is still picked up by a pane that has not overridden that option.
- **AppKit / UIKit**: Source: `DocumentEditorViewController.swift` (`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/DocumentPane/`), AppKit-only — `NSViewController` with a plain `NSView` root, `NSHostingView` hosting a private `DocumentEditorPaneView` SwiftUI struct that forwards to `FileEditorView`, `NSStackView` (vertical, `spacing: 0`, `distribution: .fill`) for breadcrumb-over-content layout, `NSButton` (`bezelStyle: .rounded`) for the reset button, `WindowOptionsToggle` for the three toggle rows, and Combine for observing `EditorOptionsOverride`'s published changes; nothing in this file targets UIKit/iOS. `init(coder:)` is unsupported and calls `fatalError`, since this controller is always constructed in code, never from a saved interface file (`NSCoder`). Directory detection queries `url.resourceValues(forKeys: [.isDirectoryKey])` via `try?`, defaulting to `false` on failure; `restoreStoredDocument()` checks `FileManager.default.fileExists(atPath:)` (true for a directory as well as a file) and clears the stored key when it returns `false`; `FileEditorView`'s own `openableNode` filter is what actually excludes a restored directory from being openable content. The whole controller is `@MainActor`-isolated, and `EditorOptionsOverride`'s debounced persistence is scheduled with `DispatchQueue.main.asyncAfter`, so both land on the main actor; `show(_:persist:)` is the shared internal entry point for every path that changes the displayed file. The hosted content is wrapped with `.themedRoot()` (default `paintsBackground: true`), which supplies the theme's `windowBackground` and `primaryText` colors. The dependencies threaded through to the hosted `FileEditorView` are typed as `TextDocumentStore`, `TextDocumentSaveScheduler`, and `ProjectLanguageServices?`; the pane-state dependency is typed as `PaneStateStore`, with `EphemeralPaneStateStore` as the in-memory implementation used in tests. No `Logger`/`os_log` call and no `String(localized:)`/`.strings`-catalog lookup appears anywhere in this file. A UIKit port would replace the gear-triggered popover (owned by the pane chrome, out of scope) with an options screen presented from a toolbar item, since iOS has no macOS-style gear-popover convention, and would need to post an explicit `UIAccessibility.post(notification: .screenChanged, argument:)` (or similar) when the displayed file changes, since the retitle-only signal this file provides (the title-change callback) is not itself an accessibility announcement on macOS either (see Announce state changes in Accessibility).
- **WinUI 3**: Rebuild the shell as a `UserControl` containing a two-row `Grid`: a fixed-height row (`GridLength` matching the `24`px breadcrumb height) hosting a `BreadcrumbBar`-based analogue (see the Breadcrumb View recipe) and a content row hosting the editor. Persist the open file's path per pane through an `ApplicationData.Current.LocalSettings` composite key mirroring `PaneStateStore`'s per-pane prefix, restoring it in the control's `Loaded` handler and clearing that key when `StorageFile.GetFileFromPathAsync` throws `FileNotFoundException` (mirroring **missing-file-restore**). Model the three toggles and the reset button as a `Flyout` (or `MenuFlyoutSubItem`) opened from a gear `AppBarButton`, using three `ToggleSwitch` controls bound to a small object that resolves each option as "pane override, else roaming `ApplicationData` setting" exactly as `EditorOptionsOverride` does, and refresh the flyout's `ToggleSwitch.IsOn` and the reset button's `IsEnabled` from that object's change event the same way `refreshOptionRows()` does. Route a URL this control cannot open in place through a routed or bubbled event rather than a closure, mirroring `onOpenRequest`, since WinUI favors events over stored closures for cross-control communication.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/DocumentPane/DocumentEditorViewController.swift` |

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

The `screen-reader-support` status is partial: the reset button's and each toggle's accessibility labels and identifiers are set explicitly (see Accessibility, **toggle-accessibility-identifiers**, **reset-accessibility-identity**), but this file posts no accessibility notification of its own when the displayed file changes, so any announcement to a screen reader depends entirely on the enclosing chrome (see Accessibility, Announce state changes). The `no-hardcoded-strings` status is failed because six user-facing strings in this file are hardcoded English literals with no localization mechanism (see Localization). The `state-recovery` status is partial because this file specifies only that it reads and writes one key on a caller-supplied `PaneStateStore`; the actual durability guarantee belongs to whichever concrete store the caller supplies (see Privacy, Storage).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Claude | Initial creation from source code |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed three action-style requirements to subject form and split the title-change requirement into setter and restore variants; dropped bare trailing Edge Case MUST tags; reworded the AppKit title-announcement note to cite the open accessibility question instead of asserting it; moved the internal `references` URL to `related` and added `depends-on`/`related` entries for the hosted child recipes; trimmed `tags` to the 1-5 limit; bolded the Design Decisions labels; corrected the Compliance table to cite real catalog checks and changed its `needs-review` status to `partial`; removed leftover template scaffold text from Accessibility Options; unified the hosted-content naming around `FileEditorView`, moving the private wrapper's name into the AppKit Platform Note; narrowed devc-012 to the selection node and marked devc-003/devc-032 as verified by code inspection; added test vectors for an app-wide options change and a dismissed popover; and split `clearDocument()` into a Methods list while adding `paneTitle`/`onPaneTitleChange` to Configuration |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/documents/. |
