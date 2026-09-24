---
id: 081703b7-036f-4fff-b580-d5dc9e5342d2
title: Content Viewer View
domain: agentictoolkit://recipes/content-viewer-view
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A read-only detail pane that shows a placeholder when nothing is selected,
  and a selected file or directory's icon, name, path, size, modification date,
  type, and item count when one is.
platforms:
- swift
- macos
tags:
- ui
- file-browser
- detail-panel
- metadata
- placeholder
depends-on:
- agentictoolkit://recipes/file-tree-outline-view-controller
- agentictoolkit://recipes/file-browser-view-controller
related: []
references: []
approved-by: ''
approved-date: ''
---

# Content Viewer View

## Overview

`ContentViewerView` is the detail pane of a file browser: it renders a placeholder message when nothing is selected, and a non-scrolling metadata sheet — icon, name, type, full path, size, modification date, and item count — when a `FileTreeNode` is selected. It performs no filesystem access of its own; every value it shows was already computed onto the `FileTreeNode` (or, for package display names, supplied by the caller's `FileTreeConfig`) before this view ever sees it. The view is a pure function of its two inputs (`selectedNode`, `config`); it holds no state of its own.

## Behavioral Requirements

- **show-placeholder-without-selection**: The component MUST render the placeholder view (icon plus message) when `selectedNode` is `nil`.
- **show-detail-with-selection**: The component MUST render the file detail view, passing it the selected node and `config`, when `selectedNode` is non-`nil`.
- **fill-available-space**: The component MUST expand to fill all available width and height, in both the placeholder and the detail state.
- **placeholder-icon-style**: The placeholder MUST display the SF Symbol `doc.text.magnifyingglass` at a 48pt system image size, in the theme's `tertiaryText` color.
- **placeholder-message-text**: The placeholder MUST display the literal text "Select a file to view its details" in the theme's `heading` text role and `secondaryText` color.
- **header-icon-symbol**: The detail view's header MUST display the icon named by `node.systemImageName` at a 40pt system image size.
- **header-icon-color-package**: The header icon MUST render in the theme's `warning` color when the selected node is a package (`node.isPackage`).
- **header-icon-color-directory**: The header icon MUST render in the theme's `accent` color when the selected node is a directory and is not a package.
- **header-icon-color-swift-or-json**: The header icon MUST render in the theme's `warning` color when the selected node is a file whose extension, compared case-insensitively, is `swift` or `json`.
- **header-icon-color-markdown**: The header icon MUST render in the theme's `accent` color when the selected node is a file whose extension, compared case-insensitively, is `md` or `markdown`.
- **header-icon-color-default**: The header icon MUST render in the theme's `secondaryText` color when the selected node is a file whose extension matches none of the cases above, including a file with no extension.
- **header-name-text**: The detail view's header MUST display `node.name` in the theme's `title` text role, limited to 2 lines, center-aligned.
- **header-type-description-text**: The detail view's header MUST display the computed type description (see `type-description-*` requirements) directly below the name, in the theme's `caption` text role and `secondaryText` color.
- **divider-between-header-and-grid**: The detail view MUST render a horizontal divider between the header and the metadata grid.
- **grid-path-row-always-shown**: The metadata grid MUST always include a "Path:" row whose value is `node.url.path`.
- **grid-path-value-selectable**: The "Path:" row's value text MUST be user-selectable, unlike every other value in the grid.
- **grid-path-line-limit**: The "Path:" row's value text MUST be limited to 3 lines, with SwiftUI's default (tail) truncation.
- **grid-size-row-conditional**: The metadata grid MUST include a "Size:" row, showing `node.fileSize` formatted by a `ByteCountFormatter` configured with `.file` count style, if and only if `node.fileSize` is non-`nil`.
- **grid-modified-row-conditional**: The metadata grid MUST include a "Modified:" row, showing `node.modificationDate` formatted by a `DateFormatter` configured with long date style and medium time style, if and only if `node.modificationDate` is non-`nil`.
- **grid-type-row-always-shown**: The metadata grid MUST always include a "Type:" row whose value is the computed type description.
- **grid-extension-row-conditional**: The metadata grid MUST include an "Extension:" row, showing `node.url.pathExtension` prefixed with a literal `.`, if and only if the node is not a directory and its path extension is non-empty.
- **grid-items-row-conditional**: The metadata grid MUST include an "Items:" row, showing the count of `node.children`, if and only if `node.children` is non-`nil`.
- **grid-label-color**: Every metadata grid row's label (e.g. "Path:", "Size:") MUST render in the theme's `secondaryText` color, trailing-aligned within the label column.
- **grid-value-text-role**: The metadata grid's values MUST render in the theme's `body` text role.
- **type-description-package**: The type description MUST be `config.packageDisplayNames[extension]` when the node is a package and that extension has a configured display name, and the literal text "Package" when the node is a package with no configured display name for its extension.
- **type-description-directory**: The type description MUST be the literal text "Directory" when the node is a directory and is not a package.
- **type-description-known-extension**: The type description for a file MUST be the fixed string for its extension (compared case-insensitively) from the following mapping: `swift`→"Swift Source File", `json`→"JSON File", `md`/`markdown`→"Markdown Document", `txt`/`text`→"Text File", `plist`→"Property List", `entitlements`→"Entitlements File", `xcodeproj`→"Xcode Project", `xcworkspace`→"Xcode Workspace", `png`→"PNG Image", `jpg`/`jpeg`→"JPEG Image", `svg`→"SVG Image", `gif`→"GIF Image", `sh`→"Shell Script", `zsh`→"Zsh Script", `bash`→"Bash Script", `py`→"Python Script", `js`→"JavaScript File", `ts`→"TypeScript File", `css`→"CSS Stylesheet", `html`→"HTML Document", `yaml`/`yml`→"YAML File", `toml`→"TOML File", `gitignore`→"Git Ignore Rules".
- **type-description-fallback-extension**: The type description for a file whose extension matches none of the known cases MUST be `"<EXTENSION>" uppercased, followed by " File"` when the extension is non-empty, and the literal text "File" when the extension is empty.
- **no-filesystem-access-in-view**: The component MUST NOT perform any file system read of its own; every value it displays MUST already be present on the `FileTreeNode` or `FileTreeConfig` it was given.

## Appearance

- **Corner radius**: None. No corner radius is set on the view or any of its subviews.
- **Padding**: Placeholder `VStack` spacing 12pt between icon and message. Header `VStack` spacing 8pt between icon, name, and type description, with 20pt padding below the header. Divider inset 40pt from each side. Metadata `Grid` horizontal spacing 16pt between columns, vertical spacing 12pt between rows, with 20pt padding above the grid and 40pt padding on each side. The whole detail view is padded 40pt from the top.
- **Font**:
  - Placeholder message — theme `heading` role (default style: 15pt, semibold).
  - Header name — theme `title` role (default style: 22pt, semibold).
  - Header type description — theme `caption` role (default style: 11pt, regular).
  - Every grid label and value — theme `body` role (default style: 13pt, regular).
  - The placeholder icon (48pt) and the header icon (40pt) are set via a literal `Image(...).font(.system(size:))` call rather than through `theme.font(_:)`, so, unlike every text element in this view, neither icon's size scales with the theme's `sizeScale` text-size preference.
- **Background**: None. No background color is set on the view or any subview; it renders on whatever background its container already painted.
- **Foreground/Text**: Placeholder icon — theme `tertiaryText`. Placeholder message — theme `secondaryText`. Header icon — see `header-icon-color-*` requirements (theme `warning`, `accent`, or `secondaryText` depending on the node). Header type description and every grid label — theme `secondaryText`. Header name and every grid value (path, size, modified date, type, extension, item count) — no explicit foreground is set; each inherits the ambient foreground color, which is the theme's `primaryText` when this view sits under a `.themedRoot()` ancestor.
- **Border**: None specified in source.
- **Shadow**: None specified in source.
- **Min/Max size**: `.frame(maxWidth: .infinity, maxHeight: .infinity)` is applied both to the top-level `Group` and independently to each of the placeholder and detail subviews, so the pane always expands to fill its container; no minimum width or height is set anywhere.

## States

| State | Appearance change |
|-------|------------------|
| No selection (`selectedNode == nil`) | Shows the placeholder: 48pt magnifying-glass-over-document icon in `tertiaryText`, heading-styled message in `secondaryText` |
| Selection — directory (not a package) | Header icon in `accent`; Type row reads "Directory"; Items row shown only if `children != nil`; Extension row never shown, because the node's `isDirectory` is true |
| Selection — package | Header icon in `warning`; Type row reads the configured display name or "Package"; neither the Items row nor the Extension row is shown, because a package node has no `children` and `isDirectory` is true |
| Selection — file, recognized extension | Header icon in `warning`, `accent`, or `secondaryText` per extension; Type and Extension rows both shown |
| Selection — file, unrecognized extension | Type row reads "`<EXTENSION>` File"; Extension row shown |
| Selection — file, no extension | Type row reads "File"; Extension row NOT shown, because the extension is empty |
| Pressed | Not applicable: `ContentViewerView` contains no button, tap target, or other interactive control — every element is static display. |
| Focused | Not applicable: nothing in the view is focusable; no `Button`, `TextField`, or other focusable control appears in source. |
| Disabled | Not applicable: the view has no enabled/disabled concept; nothing in it is interactive. |
| Loading | Not applicable: `body` is computed synchronously from properties already resolved on the given `FileTreeNode`; there is no asynchronous fetch and no loading indicator in source. |

## Accessibility

- **Role/trait**: Every `Text` in this view carries SwiftUI's default accessibility behavior — it is exposed as a static text element and its string is spoken verbatim. Every `Image(systemName:)` (the placeholder icon and the header icon) carries SwiftUI's automatically generated accessibility label derived from the SF Symbol's name; the source neither overrides nor suppresses it.
- **Label requirements**: Each grid row's label (e.g. "Path:") and its value (e.g. the path string) are two separate `Text` views, not one composed label, so each is exposed to VoiceOver as its own accessibility element rather than a single "Path: /x/y" utterance.
- **Announce state changes**: NEEDS REVIEW: Not implemented in source. Switching `selectedNode` from `nil` to a value (or from one node to another) replaces the `Group`'s content, but the source posts no explicit accessibility notification around that replacement. Whether a VoiceOver user already focused in this pane is told the content changed depends on SwiftUI/AppKit's own automatic change detection, which cannot be confirmed from this source file alone. Settling it needs either a VoiceOver test pass across a selection change, or an explicit accessibility-notification addition to the view.
- **Minimum tap target**: Not applicable: `ContentViewerView` targets macOS pointer input and contains no interactive control, so no tap or click target exists to size.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| content-viewer-view-001 | show-placeholder-without-selection | `selectedNode = nil` | The placeholder view renders; no metadata grid appears |
| content-viewer-view-002 | show-detail-with-selection | `selectedNode` = a file node | The file detail view renders with that node's data; the placeholder does not appear |
| content-viewer-view-003 | fill-available-space | Host the view in a 400×300 container, in both states | The view's rendered frame fills the full 400×300 container in each state |
| content-viewer-view-004 | placeholder-icon-style | `selectedNode = nil`; inspect the placeholder icon | Symbol is `doc.text.magnifyingglass`, font size 48, color equals `theme.tertiaryText` |
| content-viewer-view-005 | placeholder-message-text | `selectedNode = nil`; inspect the placeholder text | Text reads exactly "Select a file to view its details"; font equals `theme.font(.heading)`; color equals `theme.secondaryText` |
| content-viewer-view-006 | header-icon-symbol | `selectedNode` = a directory node | Header icon's symbol equals `node.systemImageName`; font size 40 |
| content-viewer-view-007 | header-icon-color-package | `selectedNode.isPackage == true` | Header icon color equals `theme.warning` |
| content-viewer-view-008 | header-icon-color-directory | `selectedNode.isDirectory == true`, `isPackage == false` | Header icon color equals `theme.accent` |
| content-viewer-view-009 | header-icon-color-swift-or-json | `selectedNode` is a file with extension `SWIFT` (mixed case) | Header icon color equals `theme.warning` |
| content-viewer-view-010 | header-icon-color-markdown | `selectedNode` is a file with extension `markdown` | Header icon color equals `theme.accent` |
| content-viewer-view-010b | header-icon-color-markdown | `selectedNode` is a file with extension `md` | Header icon color equals `theme.accent` |
| content-viewer-view-011 | header-icon-color-default | `selectedNode` is a file with extension `png` | Header icon color equals `theme.secondaryText` |
| content-viewer-view-012 | header-name-text | `selectedNode.name` = a 120-character string | Name renders in `theme.font(.title)`, wraps to at most 2 lines, center-aligned |
| content-viewer-view-013 | header-type-description-text | `selectedNode` is a directory | Text below the name reads "Directory", in `theme.font(.caption)` and `theme.secondaryText` |
| content-viewer-view-014 | divider-between-header-and-grid | Any selected node | Exactly one `Divider` appears between the header block and the metadata grid |
| content-viewer-view-015 | grid-path-row-always-shown | `selectedNode.url.path` = `/Users/x/a.txt` | A "Path:" row appears with value "/Users/x/a.txt" |
| content-viewer-view-016 | grid-path-value-selectable | Inspect the Path row's value text | `textSelection` is `.enabled` on that text; no other grid value has selection enabled |
| content-viewer-view-016c | grid-path-line-limit | `selectedNode.url.path` long enough to exceed 3 lines at the pane's width | The Path row's value text is clipped to 3 lines with default tail truncation; the full string remains selectable via `textSelection(.enabled)` |
| content-viewer-view-017 | grid-size-row-conditional | `selectedNode.fileSize = 2048` | A "Size:" row appears, formatted via `ByteCountFormatter` with `.file` style (e.g. "2 KB") |
| content-viewer-view-017b | grid-size-row-conditional | `selectedNode.fileSize = nil` (a directory) | No "Size:" row appears |
| content-viewer-view-018 | grid-modified-row-conditional | `selectedNode.modificationDate` = a known `Date` | A "Modified:" row appears, formatted with long date style and medium time style |
| content-viewer-view-018b | grid-modified-row-conditional | `selectedNode.modificationDate = nil` | No "Modified:" row appears |
| content-viewer-view-019 | grid-type-row-always-shown | Any selected node | A "Type:" row always appears, with the computed type description as its value |
| content-viewer-view-020 | grid-extension-row-conditional | `selectedNode` is a file with extension `swift` | An "Extension:" row appears with value ".swift" |
| content-viewer-view-020b | grid-extension-row-conditional | `selectedNode` is a directory (isDirectory = true) | No "Extension:" row appears, even if `url.pathExtension` is non-empty |
| content-viewer-view-021 | grid-items-row-conditional | `selectedNode.children` = an array of 3 nodes | An "Items:" row appears with value "3" |
| content-viewer-view-021b | grid-items-row-conditional | `selectedNode.children = nil` | No "Items:" row appears |
| content-viewer-view-021c | grid-items-row-conditional | `selectedNode.children = []` (empty, non-`nil` array) | An "Items:" row appears with value "0" |
| content-viewer-view-022 | grid-label-color | Inspect any grid row's label | Label color equals `theme.secondaryText`; label is trailing-aligned in its column |
| content-viewer-view-023 | grid-value-text-role | Inspect the grid's font modifier | The `Grid` is given `.font(theme.font(.body))` |
| content-viewer-view-024 | type-description-package | `isPackage = true`, extension `{{app_name_lower}}-proj`, `config.packageDisplayNames = ["{{app_name_lower}}-proj": "{{app_name}} Project Package"]` | Type description reads "{{app_name}} Project Package" |
| content-viewer-view-024b | type-description-package | `isPackage = true`, extension `foo`, `config.packageDisplayNames` has no entry for `foo` | Type description reads "Package" |
| content-viewer-view-025 | type-description-directory | `isDirectory = true`, `isPackage = false` | Type description reads "Directory" |
| content-viewer-view-026 | type-description-known-extension | File extension `py` | Type description reads "Python Script" |
| content-viewer-view-026b | type-description-known-extension | File extension `JSON` (mixed case) | Type description reads "JSON File" |
| content-viewer-view-026c | type-description-known-extension | File extension `gitignore` | Type description reads "Git Ignore Rules" |
| content-viewer-view-026d | type-description-known-extension | Each extension in the `type-description-known-extension` mapping (`swift`, `json`, `md`, `markdown`, `txt`, `text`, `plist`, `entitlements`, `xcodeproj`, `xcworkspace`, `png`, `jpg`, `jpeg`, `svg`, `gif`, `sh`, `zsh`, `bash`, `py`, `js`, `ts`, `css`, `html`, `yaml`, `yml`, `toml`, `gitignore`), compared case-insensitively | Each extension's type description equals the fixed string listed for it in the `type-description-known-extension` requirement |
| content-viewer-view-027 | type-description-fallback-extension | File extension `rs` (unrecognized) | Type description reads "RS File" |
| content-viewer-view-027b | type-description-fallback-extension | File with empty extension | Type description reads "File" |
| content-viewer-view-028 | no-filesystem-access-in-view | Render the view with a `selectedNode` pointing at a path that no longer exists on disk | The view renders using only the node's already-resolved properties; it makes no new file system call and does not crash |

## Edge Cases

- **Null input — no selection**: `selectedNode == nil` renders the placeholder only; no grid, header, or divider appears. MUST (see `show-placeholder-without-selection`).
- **Null input — no file size**: `node.fileSize == nil` (always true for directories, and possible for a file whose attributes read failed upstream) omits the "Size:" row entirely rather than showing a placeholder value. MUST (see `grid-size-row-conditional`).
- **Null input — no modification date**: `node.modificationDate == nil` omits the "Modified:" row entirely. MUST (see `grid-modified-row-conditional`).
- **Null input — no children**: `node.children == nil` omits the "Items:" row entirely. Per `agentictoolkit://recipes/file-tree-outline-view-controller`'s Design Decision on `FileTreeNode`'s children semantics, `nil` covers every file, every package, and any directory that has already been read and found to have no children; `FileTreeNode` deliberately reserves an empty array (`[]`) for a directory whose children have not been read yet (see the next edge case). MUST (see `grid-items-row-conditional`).
- **Boundary — children not yet loaded**: `node.children == []` (an empty, non-`nil` array — per `agentictoolkit://recipes/file-tree-outline-view-controller`, a directory whose children have not been read yet) still satisfies `node.children != nil`, so the "Items:" row is shown with value "0" — indistinguishable, from this view alone, from a directory that was read and genuinely has zero children. MUST (see `grid-items-row-conditional`).
- **Empty input — no extension**: A file with an empty `pathExtension` omits the "Extension:" row and reports the type description as the literal "File" rather than "` File"` with a blank extension. MUST (see `grid-extension-row-conditional`, `type-description-fallback-extension`).
- **Boundary — very long name**: `node.name` longer than fits two lines is clipped to 2 lines (`lineLimit(2)`) with SwiftUI's default (tail) truncation, since the source sets no `truncationMode` — unlike this pane's own Path row, which allows 3 lines before truncating, also with the default tail mode. MUST.
- **Boundary — very long path**: `node.url.path` longer than fits 3 lines is clipped to 3 lines with default tail truncation, but because `textSelection(.enabled)` is set on that value, the full untruncated string remains selectable and copyable regardless of what is visually clipped. MUST (see `grid-path-line-limit`, `grid-path-value-selectable`).
- **Boundary — zero-byte file**: `node.fileSize == 0` still satisfies `fileSize != nil`, so the "Size:" row is shown, formatted by `ByteCountFormatter` (e.g. "Zero KB" under its default settings). MUST.
- **Boundary — package with an extension**: A package node (`isPackage == true`) has `isDirectory == true`, so its "Extension:" row is never shown even though its `url.pathExtension` is non-empty — the row's condition checks `!isDirectory`, not `!isPackage`. MUST (see `grid-extension-row-conditional`).
- **Concurrent access**: `FileTreeNode.children`, `childrenLoaded`, and `gitStatus` are `@Published` and can be mutated asynchronously from a background queue (`loadChildrenIfNeeded()` dispatches its read, then assigns `children` back on the main queue). `FileDetailView` holds `node` as a plain `let`, not `@ObservedObject`, so a `children` mutation that happens while this node's detail view is already on screen does not, by itself, trigger this view to re-render its "Items:" row; the row reflects whichever `children` value was current when this view's body was last evaluated. This is a known limitation of the current implementation, produced by `let node`'s lack of observation — not a requirement other platform implementations are expected to reproduce (see the Design Decisions section).
- **Error states**: Not applicable at this layer. `ContentViewerView` performs no file system operation of its own; `node.fileSize` and `node.modificationDate` are populated — or left `nil` on a failed read — by `FileTreeNode`'s own initializer, which silently discards a failed `attributesOfItem(atPath:)` call before this view ever runs. This view's only response to that upstream failure is the already-covered `nil` case (see `grid-size-row-conditional`, `grid-modified-row-conditional`).
- **Offline or disconnected state**: Not applicable. `ContentViewerView` performs no networking of any kind; it only formats and lays out properties already present on the `FileTreeNode` and `FileTreeConfig` it is given.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `selectedNode` | `FileTreeNode?` | required, set at init | The file or directory to describe; `nil` shows the placeholder. |
| `config` | `FileTreeConfig` | required, set at init | Supplies `packageDisplayNames`, used only when the selected node is a package (see `type-description-package`). |

## Deep Linking

Not applicable: `ContentViewerView` has no URL scheme, route, or deep-link entry point in source. It renders a `selectedNode` already chosen and supplied by its owner (a file tree/browser), and initiates no navigation of its own.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `Select a file to view its details` (SwiftUI `Text` literal, a `LocalizedStringKey`) | Select a file to view its details | Placeholder message shown with no selection |
| `Path:` (SwiftUI `Text` literal, a `LocalizedStringKey`) | Path: | Grid row label |
| `Size:` (SwiftUI `Text` literal, a `LocalizedStringKey`) | Size: | Grid row label |
| `Modified:` (SwiftUI `Text` literal, a `LocalizedStringKey`) | Modified: | Grid row label |
| `Type:` (SwiftUI `Text` literal, a `LocalizedStringKey`) | Type: | Grid row label |
| `Extension:` (SwiftUI `Text` literal, a `LocalizedStringKey`) | Extension: | Grid row label |
| `Items:` (SwiftUI `Text` literal, a `LocalizedStringKey`) | Items: | Grid row label |
| (none — hardcoded literal) | Directory | Type description for a directory |
| (none — hardcoded literal) | Package | Type description fallback for a package with no configured display name |
| (none — hardcoded literal) | Swift Source File / JSON File / Markdown Document / Text File / Property List / Entitlements File / Xcode Project / Xcode Workspace / PNG Image / JPEG Image / SVG Image / GIF Image / Shell Script / Zsh Script / Bash Script / Python Script / JavaScript File / TypeScript File / CSS Stylesheet / HTML Document / YAML File / TOML File / Git Ignore Rules | Type description for a file, by recognized extension (see `type-description-known-extension`) |
| (none — hardcoded literal) | `<EXTENSION> File` / File | Type description fallback for an unrecognized or absent extension |

The seven fixed labels are passed to `Text("…")` as literals, so SwiftUI treats each as a `LocalizedStringKey`: they are looked up in the bundle's string table and fall back to the literal when no translation exists. NEEDS REVIEW: Not implemented in source. The type descriptions (`Directory`, `Package`, the per-extension names, and the `<EXTENSION> File` fallback) are computed `String` values passed to `Text(_:)` as a `StringProtocol`, which SwiftUI renders verbatim with no lookup; whether those should be localized is a product decision the source does not make.

## Accessibility Options

Document which accessibility display options this component responds to:

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the source contains no animation, transition, or animation context anywhere in `ContentViewerView.swift`, so there is no motion for this setting to reduce. |
| Increase Contrast | Not applicable: every color in this view is a semantic theme role (`theme.tertiaryText`, `theme.secondaryText`, `theme.warning`, `theme.accent`, or the inherited ambient foreground) resolved through `SwiftUIPalette`; no fixed, non-semantic color literal appears in source, so contrast adaptation is the active theme's responsibility, not this component's. |
| Differentiate Without Color | Not applicable: no state or meaning in this component is conveyed by color alone. The header icon's color varies by file type (see `header-icon-color-*`), but the same information is always also given as text, in the type description shown right below it. |

## Feature Flags

Not applicable: no feature flag is defined or checked anywhere in `ContentViewerView.swift`.

## Analytics

Not applicable: no analytics event is emitted anywhere in `ContentViewerView.swift`.

## Privacy

- **Data collected**: None of its own. The view displays file metadata (name, path, size, modification date, type, child count) already resolved onto the `FileTreeNode` it is given; it reads and collects nothing itself.
- **Storage**: Not applicable — the view persists nothing; every displayed value is recomputed from `selectedNode` and `config` on each render and held only in memory for that render.
- **Transmission**: Not applicable — the view performs no networking and sends nothing anywhere.
- **Retention**: Not applicable — no data is retained beyond the current `selectedNode`'s in-memory properties.

## Logging

Not applicable: no logging call appears anywhere in `ContentViewerView.swift`.

## Platform Notes

- **SwiftUI**: This is the source implementation: `ContentViewerView.swift` (packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Views/), a `Group` switching between a private `PlaceholderView` and a private `FileDetailView`, both reading colors and fonts from `@Environment(\.theme)` (a `SwiftUIPalette`), with `Grid`/`GridRow` for the metadata table and static `ByteCountFormatter`/`DateFormatter` instances shared across renders.
- **Compose**: A Jetpack Compose port would branch a `Box` on whether a node is selected, using a `Column` for the placeholder (an `Icon` plus `Text`) and a second `Column` for the detail view; Compose's `Grid`-like layouts (a two-column `Row`-per-`GridRow`, or `LazyVerticalGrid` for a fixed row count) reproduce the label/value pairing, and wrapping just the Path row's value `Text` in a `SelectionContainer` reproduces its selectable text, which is otherwise off by default in Compose, the reverse of SwiftUI's opt-in model.
- **React/Web**: A web port renders the same two states as a conditional block, using a `<dl>` (description list) for the metadata grid — `<dt>` for each label, `<dd>` for each value — which gives the label/value pairing built-in semantic structure that this SwiftUI `Grid` does not provide on its own; the Path value needs no special CSS to be selectable (browser text is selectable by default, the reverse of this component's explicit `textSelection(.enabled)` opt-in), and the byte-count and date formatting need explicit helpers (`Intl.NumberFormat`-based byte formatting, `Intl.DateTimeFormat` with a long/medium equivalent) in place of `ByteCountFormatter`/`DateFormatter`.
- **AppKit / UIKit**: An AppKit port would replace `Grid`/`GridRow` with an `NSGridView` (AppKit's direct, longstanding equivalent, predating SwiftUI's `Grid`) or a stack of horizontal `NSStackView` rows, `Text` with `NSTextField` (label style, non-editable, `isSelectable` set only on the Path field's value to reproduce `textSelection(.enabled)`), and the two SF Symbol images with `NSImageView` configured from `NSImage(systemSymbolName:accessibilityDescription:)`. A UIKit port (iOS) would use `UICollectionView` with a list configuration or a stack of `UIStackView` rows for the grid, `UILabel` for every text element (`UILabel` has no built-in text-selection toggle the way `NSTextField.isSelectable` does; reproducing the Path row's selectable behavior needs `UITextView` configured as non-editable but selectable), and `UIImageView` with `UIImage(systemName:)` for the icons.
- **WinUI 3**: There is no single WinUI 3 control that is this whole component's analogue; compose it from a `Grid` (WinUI's `Grid`, laid out with explicit `RowDefinitions`/`ColumnDefinitions`, is the direct equivalent of SwiftUI's `Grid`/`GridRow` used here) for the metadata rows, with a `FontIcon` or `ImageIcon` for the two SF Symbol icons (mapped to Segoe Fluent Icons glyphs, since WinUI has no SF Symbol equivalent) and `TextBlock IsTextSelectionEnabled="True"` on the Path row's value only, mirroring `textSelection(.enabled)`'s selective opt-in (every other `TextBlock` defaults to `IsTextSelectionEnabled="False"`, matching this component's non-selectable labels and other values). Reproduce the conditional rows (`Size:`, `Modified:`, `Extension:`, `Items:`) with `Visibility` bindings driven by the same null checks as `grid-size-row-conditional` etc., rather than by removing and re-adding `Grid` rows at runtime.

## Design Decisions

- **Decision**: The header icon's color maps file-extension "brand" associations onto the theme's status roles: `swift`/`json` land on `warning`, `md`/`markdown` on `accent`.
  **Rationale**: `headerIconColor`'s own source comment (`ContentViewerView.swift:199-204`) draws this as an analogy to `SwiftUIPalette.color(named:)`'s conventional-color-to-role mapping used elsewhere in the toolkit (orange/yellow → `warning`, blue → `accent`) — `headerIconColor` itself switches directly on the file extension rather than calling that mapping function, so `swift`/`json` landing on `warning` and `md`/`markdown` landing on `accent` mirrors, but does not literally reuse, that shared mapping.
  **Approved**: pending

- **Decision**: A stale "Items:" row — showing a `children` count that no longer matches the node's current, asynchronously-updated value — is treated as a known limitation of this SwiftUI implementation (see the **Concurrent access** edge case), not a contract other platform implementations are required to reproduce.
  **Rationale**: The staleness is a side effect of `FileDetailView` holding `node` as a plain `let` rather than observing it (`@ObservedObject`); nothing in source suggests this was an intentional design choice rather than an oversight, so it should not be codified as required behavior for a port to copy.
  **Approved**: pending

- **Decision**: Each metadata grid row keeps its label and value as two separate `Text` elements — e.g. two accessibility elements for "Path:" and its value — rather than combining them with `.accessibilityElement(children: .combine)`.
  **Rationale**: Not stated in source: no accessibility modifier is applied to any `GridRow` or `Text` in `ContentViewerView.swift`, so each `Text` keeps SwiftUI's default per-element accessibility behavior. Combining each row into one spoken utterance (e.g. "Path: /Users/x/a.txt") would need `.accessibilityElement(children: .combine)` added to each `GridRow`, which the source does not do; a port needs to decide whether to copy the current split behavior or add the combine modifier.
  **Approved**: pending

- **Decision**: No explicit accessibility change notification is posted when `selectedNode` changes and the `Group`'s content is replaced.
  **Rationale**: Not stated in source: `ContentViewerView.swift` contains no accessibility-notification call anywhere. Whatever announcement (if any) a VoiceOver user hears on selection change comes entirely from SwiftUI/AppKit's own automatic change detection (see the Accessibility section's open question on this); a port needs to decide whether that is sufficient or whether an explicit notification should be added.
  **Approved**: pending

- **Decision**: `byteCountFormatter` and `dateFormatter` are declared as `static let` constants on `FileDetailView` rather than being created inside `body`.
  **Rationale**: A `static let` is created once and reused for every re-evaluation of `body` and for every `FileDetailView` instance, instead of allocating a fresh `ByteCountFormatter`/`DateFormatter` on each render.
  **Approved**: pending

- **Decision**: The placeholder icon (48pt) and the header icon (40pt) are sized with literal `Image(...).font(.system(size:))` calls rather than `theme.font(_:)`.
  **Rationale**: Not stated in source. The observable effect is that both icons stay a fixed point size regardless of the theme's `sizeScale` text-size preference, while every text element in this view (which does call `theme.font(_:)`) scales with it.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | partial | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [unicode-support](agenticdevelopercookbook://compliance/internationalization#unicode-support) | passed | Internationalization |
| [rtl-layout-support](agenticdevelopercookbook://compliance/internationalization#rtl-layout-support) | passed | Internationalization |

The accessibility statuses are partial because this view relies entirely on SwiftUI's default `Text`/`Image` accessibility behavior — it sets no custom label, trait, or accessibility notification of its own — and because whether a selection change is announced to an already-focused VoiceOver user is unconfirmed from source (see the Accessibility section's marker). Dynamic-type-support is partial because text scales with the theme's own `sizeScale` preference rather than the system's native Dynamic Type category, and the two icon sizes do not scale with either. `no-hardcoded-strings` failed because the computed type description strings (`Directory`, `Package`, the per-extension names, and the `<EXTENSION> File` fallback — see Localization) are `String` values passed to `Text(_:)` with no localization lookup; the seven fixed grid/placeholder labels are literals passed directly to `Text("…")`, which SwiftUI does look up as a `LocalizedStringKey`. The internationalization passes hold because every string is plain Unicode `Text`, and the grid's leading/trailing alignment mirrors automatically for right-to-left locales.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Claude | Initial creation from source code |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: add depends-on cross-references; add grid-path-line-limit requirement and vector; reword the header-icon-color Design Decision as an analogy rather than causation; reframe the concurrent-access edge case as a known limitation and add a pending Design Decision for it; fix grid-label-color to say trailing-aligned; clarify children nil-vs-empty semantics with a new edge case and vector; remove a fabricated Compose API and a dangling Rule 15 reference; split the Font appearance bullet by role; add extension-mapping and md icon-color test vectors; add pending Design Decisions for split label/value accessibility elements and the missing selection-change notification; neutralize an app-specific test-vector value; narrow the no-hardcoded-strings compliance rationale; reword Overview wording and align summary with it |
