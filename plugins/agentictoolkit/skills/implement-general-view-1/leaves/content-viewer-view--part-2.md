<!-- leaf: implement-general-view-1/content-viewer-view--part-2 · source: content-viewer-view.md -->

# Content Viewer View — continued (part 2)

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

The seven fixed labels are passed to `Text("…")` as literals, so SwiftUI treats each as a `LocalizedStringKey`: they are looked up in the bundle's string table and fall back to the literal when no translation exists. The type descriptions (`Directory`, `Package`, the per-extension names, and the `<EXTENSION> File` fallback) are computed `String` values passed to `Text(_:)` as a `StringProtocol`, which SwiftUI renders verbatim with no lookup: these are hardcoded English strings with no localization of their own.

## Accessibility Options

Document which accessibility display options this component responds to:

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the source contains no animation, transition, or animation context anywhere in `ContentViewerView.swift`, so there is no motion for this setting to reduce. |
| Increase Contrast | Not applicable: every color in this view is a semantic theme role (`theme.tertiaryText`, `theme.secondaryText`, `theme.warning`, `theme.accent`, or the inherited ambient foreground) resolved through `SwiftUIPalette`; no fixed, non-semantic color literal appears in source, so contrast adaptation is the active theme's responsibility, not this component's. |
| Differentiate Without Color | Not applicable: no state or meaning in this component is conveyed by color alone. The header icon's color varies by file type (see `header-icon-color-*`), but the same information is always also given as text, in the type description shown right below it. |

## Privacy

- **Data collected**: None of its own. The view displays file metadata (name, path, size, modification date, type, child count) already resolved onto the `FileTreeNode` it is given; it reads and collects nothing itself.
- **Storage**: Not applicable — the view persists nothing; every displayed value is recomputed from `selectedNode` and `config` on each render and held only in memory for that render.
- **Transmission**: Not applicable — the view performs no networking and sends nothing anywhere.
- **Retention**: Not applicable — no data is retained beyond the current `selectedNode`'s in-memory properties.

## Platform Notes

- **SwiftUI**: This is the source implementation: `ContentViewerView.swift` (packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Views/), a `Group` switching between a private `PlaceholderView` and a private `FileDetailView`, both reading colors and fonts from `@Environment(\.theme)` (a `SwiftUIPalette`), with `Grid`/`GridRow` for the metadata table and static `ByteCountFormatter`/`DateFormatter` instances shared across renders.
- **Compose**: A Jetpack Compose port would branch a `Box` on whether a node is selected, using a `Column` for the placeholder (an `Icon` plus `Text`) and a second `Column` for the detail view; Compose's `Grid`-like layouts (a two-column `Row`-per-`GridRow`, or `LazyVerticalGrid` for a fixed row count) reproduce the label/value pairing, and wrapping just the Path row's value `Text` in a `SelectionContainer` reproduces its selectable text, which is otherwise off by default in Compose, the reverse of SwiftUI's opt-in model.
- **React/Web**: A web port renders the same two states as a conditional block, using a `<dl>` (description list) for the metadata grid — `<dt>` for each label, `<dd>` for each value — which gives the label/value pairing built-in semantic structure that this SwiftUI `Grid` does not provide on its own; the Path value needs no special CSS to be selectable (browser text is selectable by default, the reverse of this component's explicit `textSelection(.enabled)` opt-in), and the byte-count and date formatting need explicit helpers (`Intl.NumberFormat`-based byte formatting, `Intl.DateTimeFormat` with a long/medium equivalent) in place of `ByteCountFormatter`/`DateFormatter`.
- **AppKit / UIKit**: An AppKit port would replace `Grid`/`GridRow` with an `NSGridView` (AppKit's direct, longstanding equivalent, predating SwiftUI's `Grid`) or a stack of horizontal `NSStackView` rows, `Text` with `NSTextField` (label style, non-editable, `isSelectable` set only on the Path field's value to reproduce `textSelection(.enabled)`), and the two SF Symbol images with `NSImageView` configured from `NSImage(systemSymbolName:accessibilityDescription:)`. A UIKit port (iOS) would use `UICollectionView` with a list configuration or a stack of `UIStackView` rows for the grid, `UILabel` for every text element (`UILabel` has no built-in text-selection toggle the way `NSTextField.isSelectable` does; reproducing the Path row's selectable behavior needs `UITextView` configured as non-editable but selectable), and `UIImageView` with `UIImage(systemName:)` for the icons.
- **WinUI 3**: There is no single WinUI 3 control that is this whole component's analogue; compose it from a `Grid` (WinUI's `Grid`, laid out with explicit `RowDefinitions`/`ColumnDefinitions`, is the direct equivalent of SwiftUI's `Grid`/`GridRow` used here) for the metadata rows, with a `FontIcon` or `ImageIcon` for the two SF Symbol icons (mapped to Segoe Fluent Icons glyphs, since WinUI has no SF Symbol equivalent) and `TextBlock IsTextSelectionEnabled="True"` on the Path row's value only, mirroring `textSelection(.enabled)`'s selective opt-in (every other `TextBlock` defaults to `IsTextSelectionEnabled="False"`, matching this component's non-selectable labels and other values). Reproduce the conditional rows (`Size:`, `Modified:`, `Extension:`, `Items:`) with `Visibility` bindings driven by the same null checks as `grid-size-row-conditional` etc., rather than by removing and re-adding `Grid` rows at runtime.

## Design Decisions

- **Decision**: The header icon's color maps file-extension "brand" associations onto the theme's status roles: `swift`/`json` land on `warning`, `md`/`markdown` on `accent`.
  **Rationale**: `headerIconColor`'s own source comment (`ContentViewerView.swift`) draws this as an analogy to `SwiftUIPalette.color(named:)`'s conventional-color-to-role mapping used elsewhere in the toolkit (orange/yellow → `warning`, blue → `accent`) — `headerIconColor` itself switches directly on the file extension rather than calling that mapping function, so `swift`/`json` landing on `warning` and `md`/`markdown` landing on `accent` mirrors, but does not literally reuse, that shared mapping.
  **Approved**: pending

- **Decision**: A stale "Items:" row — showing a `children` count that no longer matches the node's current, asynchronously-updated value — is treated as a known limitation of this SwiftUI implementation (see the **Concurrent access** edge case), not a contract other platform implementations are required to reproduce.
  **Rationale**: The staleness is a side effect of `FileDetailView` holding `node` as a plain `let` rather than observing it (`@ObservedObject`); nothing in source suggests this was an intentional design choice rather than an oversight, so it should not be codified as required behavior for a port to copy.
  **Approved**: pending

- **Decision**: Each metadata grid row keeps its label and value as two separate `Text` elements — e.g. two accessibility elements for "Path:" and its value — rather than combining them with `.accessibilityElement(children: .combine)`.
  **Rationale**: Not stated in source: no accessibility modifier is applied to any `GridRow` or `Text` in `ContentViewerView.swift`, so each `Text` keeps SwiftUI's default per-element accessibility behavior. Combining each row into one spoken utterance (e.g. "Path: /Users/x/a.txt") would need `.accessibilityElement(children: .combine)` added to each `GridRow`, which the source does not do; a port needs to decide whether to copy the current split behavior or add the combine modifier.
  **Approved**: pending

- **Decision**: No explicit accessibility change notification is posted when `selectedNode` changes and the `Group`'s content is replaced.
  **Rationale**: Not stated in source: `ContentViewerView.swift` contains no accessibility-notification call anywhere. Whatever announcement (if any) a VoiceOver user hears on selection change comes entirely from SwiftUI/AppKit's own automatic change detection (see the Accessibility section's Announce state changes item); a port needs to decide whether that is sufficient or whether an explicit notification should be added.
  **Approved**: pending

- **Decision**: `byteCountFormatter` and `dateFormatter` are declared as `static let` constants on `FileDetailView` rather than being created inside `body`.
  **Rationale**: A `static let` is created once and reused for every re-evaluation of `body` and for every `FileDetailView` instance, instead of allocating a fresh `ByteCountFormatter`/`DateFormatter` on each render.
  **Approved**: pending

- **Decision**: The placeholder icon (48pt) and the header icon (40pt) are sized with literal `Image(...).font(.system(size:))` calls rather than `theme.font(_:)`.
  **Rationale**: Not stated in source. The observable effect is that both icons stay a fixed point size regardless of the theme's `sizeScale` text-size preference, while every text element in this view (which does call `theme.font(_:)`) scales with it.
  **Approved**: pending
