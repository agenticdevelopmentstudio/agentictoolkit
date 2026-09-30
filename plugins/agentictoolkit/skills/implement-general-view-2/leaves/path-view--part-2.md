<!-- leaf: implement-general-view-2/path-view--part-2 · source: path-view.md -->

# PathView — continued (part 2)

## Platform Notes

- **SwiftUI**: Compose a `Text(path)` (or `Text("\(caption): \(path)")`) with
  `.font(.caption)`, `.foregroundStyle(.secondary)`, `.lineLimit(1)`, and
  `.truncationMode(.middle)` — SwiftUI's direct analog of `.byTruncatingMiddle`
  with `maximumNumberOfLines == 1`. Add `.help(path)` for the tooltip and
  `.accessibilityValue(path)` for the accessibility-value analogs of
  `exposes-raw-path-as-tooltip`/`exposes-raw-path-as-accessibility-value`, and
  `.textSelection(.enabled)` for `supports-text-selection`. Give the view no
  fixed frame so it shrinks to the width its container provides, mirroring
  `yields-width-to-container`.
- **Compose**: Use `Text(path, style = MaterialTheme.typography.labelSmall,
  color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1,
  overflow = TextOverflow.MiddleEllipsis)` — Compose 1.8+'s built-in
  middle-ellipsis overflow, the nearest analog to `.byTruncatingMiddle`,
  inside a layout slot with no fixed width so it shrinks like
  `yields-width-to-container`. Compose has no separate tooltip API on plain
  `Text`; expose the full `path` via `Modifier.semantics { stateDescription =
  path }` — `stateDescription` supplements what's announced the way AppKit's
  `setAccessibilityValue` does, where `contentDescription` would instead
  replace the accessible name — for the accessibility-value analog, and a
  `TooltipBox` wrapper for the visual tooltip analog.
- **React/Web**: A `<span title={path}>` (the tooltip analog) styled with
  `white-space: nowrap; overflow: hidden;` and a CSS-only end-ellipsis is not
  enough, since CSS `text-overflow` has no middle-ellipsis value; either
  split the string into head/tail segments sized against the container's
  measured width in script (recomputed on resize, the web analog of AppKit's
  cell recomputing on layout) or use a small middle-truncation utility.
  `aria-label` would replace the element's accessible name rather than add a
  value the way AppKit's `setAccessibilityValue` does; instead pair
  `aria-describedby` with a visually-hidden (`sr-only`) span holding the full
  `path` for the accessibility-value analog, make the text selectable (the
  CSS default, unless a parent sets
  `user-select: none`) for `supports-text-selection`, and `width: 100%` with
  no `min-width` so it shrinks with its container, mirroring
  `yields-width-to-container`.
- **AppKit / UIKit** (source platform): Source at
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PathView.swift`
  (this recipe's source): a macOS-only (`import AppKit`) `NSView` subclass,
  `@MainActor`, inside the `ComposableSettings` namespace, wrapping one
  `ComposableSettings.makeValueLabel`-built `ThemedLabel` reconfigured for
  middle-truncating, single-line display and pinned edge-to-edge. A UIKit
  port replaces `NSView`/`NSTextField` (`ThemedLabel`) with `UIView`/`UILabel`,
  sets `numberOfLines = 1` and `lineBreakMode = .byTruncatingMiddle` (`UILabel`'s
  direct analogs of `maximumNumberOfLines`/`lineBreakMode`), keeps the same
  horizontal-compressible priorities via
  `setContentCompressionResistancePriority(_:for:)`/
  `setContentHuggingPriority(_:for:)`, sets `accessibilityValue = path` and
  exposes the tooltip only via a custom hover/hold affordance since UIKit has
  no `NSView.toolTip` equivalent, and enables selection with
  `isUserInteractionEnabled = true` plus a `UILongPressGestureRecognizer`
  driving a `UIEditMenuInteraction` (the iOS 16 API that superseded the
  deprecated `UIMenuController`) presented via `presentEditMenu(with:)`,
  since `UILabel` has no built-in `isSelectable`. `UIView` has the same
  `init(frame:)`/`init(coder:)` initializer split as `NSView`, so a UIKit
  port can fatal-error from both exactly as `rejects-frame-only-initialization`
  and `rejects-storyboard-instantiation` require.
- **WinUI 3**: Build this as a `TextBlock`
  bound to the full `path` string through a value converter (or a small
  behavior) that performs the middle truncation itself, since XAML's
  `TextTrimming` enum (`None`, `CharacterEllipsis`, `WordEllipsis`, `Clip`)
  only trims at the trailing edge — there is no WinUI equivalent of
  `NSLineBreakMode.byTruncatingMiddle`. Recompute the head/tail split on
  `SizeChanged` (measuring candidate substrings against the `TextBlock`'s own
  `ActualWidth`, the way AppKit's cell recomputes truncation on layout), and
  keep the untruncated string separately (a bound property mirroring `path`)
  for `ToolTipService.ToolTip` and `AutomationProperties.HelpText` (or a
  custom `ValuePattern` automation peer) — WinUI's nearest analogs of
  `toolTip` and `setAccessibilityValue`; `AutomationProperties.Name` would
  replace the accessible name the way `aria-label` does elsewhere, so leave
  it to default from the bound (caption-prefixed) `TextBlock.Text`, mirroring
  AppKit's reliance on the visible string as the accessible name since no
  label override is set in source. Set `IsTextSelectionEnabled="true"` (the analog of
  `isSelectable`) so the bound `TextBlock.Text` — the full string, not the
  elided glyphs — can be selected and copied, matching
  `supports-text-selection`. Use `HorizontalAlignment="Stretch"` with no
  fixed `Width` and no `MinWidth`, the analog of `yields-width-to-container`,
  and style `Foreground`/`FontSize` from the app's secondary-text/caption
  resource keys, since WinUI 3 has no single built-in "secondary text"
  system brush the way `SemanticPalette.secondaryText` derives one.

## Design Decisions

- **Decision**: `PathView`'s label overrides `ThemedLabel`'s default
  single-line, clipped configuration by setting `usesSingleLineMode = false`
  while keeping `maximumNumberOfLines = 1`, rather than leaving
  `usesSingleLineMode = true`.
  **Rationale**: source comments state directly that "`wraps = false` rather
  than `usesSingleLineMode = true`: single-line mode is what makes the cell
  ignore `lineBreakMode`, and the line break is the whole point here" — with
  `usesSingleLineMode` left `true`, `lineBreakMode = .byTruncatingMiddle`
  would be silently ignored.
  **Approved**: pending
- **Decision**: an optional `caption` is placed at the head of the displayed
  string (`"<caption>: <path>"`), rather than after the path or in a separate
  label.
  **Rationale**: source comments explain that the head is "which middle
  truncation never eats," so placing the caption there means "the row still
  says what it is at any width" — a caption placed at the tail or the middle
  would be the first thing lost as the view narrows.
  **Approved**: pending
- **Decision**: `label.toolTip` and `label.setAccessibilityValue` are both
  set to the raw `path`, never the caption-prefixed display string, while
  selecting and copying the label's text yields the full `label.stringValue`
  (caption-prefixed, when a caption is supplied).
  **Rationale**: documented here as a source quirk rather than smoothed over.
  The source's own doc comment frames this as one guarantee — "the drawn
  text is lossy by design, so the three ways of asking for it all answer with
  the path itself" — but the three ways do not, in fact, answer identically:
  tooltip and accessibility value strip the caption while copy-via-selection
  keeps it, because copying reads `NSTextField.stringValue` (the full
  `shown` string) rather than a separately-tracked "path" value. This
  asymmetry is unchanged for this recipe; per Accessibility above, the
  caption is not exposed through any accessibility label, so the accessible
  representation carries the same gap tooltip and accessibility value do.
  **Approved**: pending
- **Decision**: the label's horizontal content-compression-resistance and
  content-hugging priorities are both lowered to `.defaultLow`.
  **Rationale**: source comments state that "a path yields its width to the
  panel instead of widening the window to stay whole — the same bargain
  every truncating label here makes," so the label is deliberately let to
  shrink to the available width instead of forcing the settings panel wider.
  **Approved**: pending
- **Decision**: force a fatal error from both `init(frame:)` and
  `init(coder:)`, leaving `init(withPath:caption:)` as the only usable
  initializer.
  **Rationale**: the view has no meaningful default state — it cannot render
  anything without a `path` string — so both inherited `NSView` initializers
  that could construct it without one are intentionally disabled rather than
  left to produce a blank row.
  **Approved**: pending
