<!-- leaf: implement-general-view-1/content-viewer-view · source: content-viewer-view.md -->

**Rules** (cite as `implement-general-view-1/content-viewer-view#<slug>`):

- `show-placeholder-without-selection` MUST
- `show-detail-with-selection` MUST
- `fill-available-space` MUST
- `placeholder-icon-style` MUST
- `placeholder-message-text` MUST
- `header-icon-symbol` MUST
- `header-icon-color-package` MUST
- `header-icon-color-directory` MUST
- `header-icon-color-swift-or-json` MUST
- `header-icon-color-markdown` MUST
- `header-icon-color-default` MUST
- `header-name-text` MUST
- `header-type-description-text` MUST
- `divider-between-header-and-grid` MUST
- `grid-path-row-always-shown` MUST
- `grid-path-value-selectable` MUST
- `grid-path-line-limit` MUST
- `grid-size-row-conditional` MUST
- `grid-modified-row-conditional` MUST
- `grid-type-row-always-shown` MUST
- `grid-extension-row-conditional` MUST
- `grid-items-row-conditional` MUST
- `grid-label-color` MUST
- `grid-value-text-role` MUST
- `type-description-package` MUST
- `type-description-directory` MUST
- `type-description-known-extension` MUST
- `type-description-fallback-extension` MUST
- `no-filesystem-access-in-view` MUST

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

## Accessibility

- **Role/trait**: Every `Text` in this view carries SwiftUI's default accessibility behavior — it is exposed as a static text element and its string is spoken verbatim. Every `Image(systemName:)` (the placeholder icon and the header icon) carries SwiftUI's automatically generated accessibility label derived from the SF Symbol's name; the source neither overrides nor suppresses it.
- **Label requirements**: Each grid row's label (e.g. "Path:") and its value (e.g. the path string) are two separate `Text` views, not one composed label, so each is exposed to VoiceOver as its own accessibility element rather than a single "Path: /x/y" utterance.
- **Announce state changes**: Switching `selectedNode` from `nil` to a value (or from one node to another) replaces the `Group`'s content, but the source posts no explicit accessibility notification of its own around that replacement — no accessibility-notification call appears anywhere in `ContentViewerView.swift`. Whatever a VoiceOver user already focused in this pane hears comes entirely from SwiftUI/AppKit's own automatic change detection, not from an explicit call in source.
- **Minimum tap target**: Not applicable: `ContentViewerView` targets macOS pointer input and contains no interactive control, so no tap or click target exists to size.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `selectedNode` | `FileTreeNode?` | required, set at init | The file or directory to describe; `nil` shows the placeholder. |
| `config` | `FileTreeConfig` | required, set at init | Supplies `packageDisplayNames`, used only when the selected node is a package (see `type-description-package`). |

