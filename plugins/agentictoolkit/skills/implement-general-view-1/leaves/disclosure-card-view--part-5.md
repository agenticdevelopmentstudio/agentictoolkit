<!-- leaf: implement-general-view-1/disclosure-card-view--part-5 · source: disclosure-card-view.md -->

# DisclosureCardView — continued (part 5)

## Platform Notes

- **SwiftUI**: Compose a custom `DisclosureGroup`-like container instead of
  the built-in `DisclosureGroup` (which has no slot for a collapsed one-line
  summary or a corner badge): a `VStack` holding a header `HStack` (optional
  leading accessory, `Text(title)` with low layout priority, a `Spacer`
  bounded by a minimum width, optional trailing accessory, and a rotating
  chevron `Button`) styled with `.background(elevatedSurfaceColor)`, and a
  conditional body below styled with `.background(surfaceColor)`. Reproduce
  the fold-independent width floor with a `.frame(minWidth:)` computed from
  both the open and folded content via `GeometryReader`/`PreferenceKey`
  measurement, since SwiftUI's conditional `if` view does not keep a
  detached branch measurable the way `NSStackView.isHidden` does. Draw the
  corner badge with `.overlay(alignment: .topTrailing)` and a small offset
  matching `cornerPeakInset`.
- **Compose**: Build the header as a `Row` with a `Modifier.background`
  matching the elevated surface color, an `Icon`/`IconButton` rotating 0↔180°
  for the disclosure state (Material has no single "disclosure triangle"
  control), and `AnimatedVisibility`/conditional composition for the body.
  Reserve the fold-independent width by measuring both the open and folded
  content with `SubcomposeLayout` and taking the wider `IntrinsicSize`,
  since a collapsed `AnimatedVisibility` composable does not otherwise keep
  its content measurable. Place the status badge with a `Box` using
  `Modifier.align(Alignment.TopEnd)` and an offset of
  `-(badgeDiameter / 2 − cornerPeakInset)` on both axes, so the badge is
  centered on the corner's arc rather than its edge.
- **React/Web**: A `<div>` with `aria-expanded` on its disclosure `<button>`
  (not `<details>`/`<summary>`, which has no slot for a collapsed one-line
  summary shown in place of the body and cannot support toggling the body
  via a CSS class rather than removal from the DOM); the header renders
  with the elevated background and a rotating disclosure `<button>`, and
  the body toggles via a CSS class (e.g. `.collapsed`) rather than
  `display: none`. Reserve the width floor by measuring both the open and
  collapsed header/body with `ResizeObserver` while both are rendered with
  `visibility: hidden; position: absolute` rather than `display: none` —
  `display: none` removes an element from measurement the way AppKit's
  `isHidden` does not. Position the status badge with `position: absolute;
  top: <peak>px; right: <peak>px; transform: translate(50%, -50%)`.
- **AppKit / UIKit** (source platform): Source at
  `packages/apple/AgenticToolkit/macOS/UI/Cards/DisclosureCardView.swift`
  (this recipe's source), plus its directory-mates `PinnedEndsLine.swift`
  (the header row's pinned-ends layout), `NSStackView+FullWidth.swift`
  (`addFullWidthArrangedSubview`, used to make the body section's rows fill
  the stack's width), and `CardFoldMemory.swift` (the host-side persistence
  and rebuild helper most callers wire this view to). This is macOS-only —
  `NSView`/`NSButton`/`NSStackView`/`NSTextField`/`NSImageView`; there is no
  UIKit code path in source. A UIKit port would replace those with
  `UIView`/a custom disclosure `UIButton` (UIKit has no built-in disclosure-
  triangle bezel style)/`UIStackView`/`UILabel`/`UIImageView`, and can reuse
  the same fold-independent width-floor technique directly, since
  `UIStackView.isHidden` behaves like `NSStackView.isHidden`: it detaches a
  hidden arranged view from the stack's layout while the view itself
  remains measurable via `intrinsicContentSize` when asked directly.
  The recipe's descriptive terms above map to these source private members:
  the card surface is `surface`; the titlebar strip is `titlebar`; the
  titlebar's bottom rule is `titlebarRule`; the title text is `titleField`
  (a `WholePointLabel`, from `CoreUI/WholePointLabel.swift` in
  AgenticToolkitCoreUI); the title status symbol is `titleStatusIcon`; the
  title row is `titleLine`; the trailing row is `trailingLine`; the
  disclosure control is `disclosure`; the content area is `content`; the
  body section is `body`; the subtitle text is `subtitleField`; the summary
  line is `summaryField`; the status badge is `statusIcon`; and the
  width-floor constraint is `contentWidthFloor`. `color(named:)`'s
  name→role map (`"red"` → `dangerColor`, `"blue"` → `accentColor`, and so
  on) is defined outside this source, in
  `external/agenticdevelopertoolkit/packages/apple/AgenticDeveloperToolkit/SourcesUI/macOS/Theme/SemanticPalette+NSColor.swift`.
- **WinUI 3** (the reason this recipe exists): WinUI 3's `Expander` control
  is the nearest built-in analog — it already pairs a `Header` with
  collapsible `Content` and a built-in chevron that flips on `IsExpanded` —
  but it has no slot for a collapsed-only summary row and no corner badge,
  and critically: setting `Visibility="Collapsed"` on `Expander.Content`
  (or on any element) makes WinUI's layout system return a zero
  `DesiredSize` from `Measure()`, unlike AppKit's `NSView.isHidden`, which
  detaches a view from the visible layout while still returning its real
  `fittingSize` on request. Porting `floors-width-to-wider-of-open-or-
  folded-content` faithfully therefore requires NOT using
  `Visibility="Collapsed"` for the hidden state; instead, keep the content
  `Opacity="0"` and non-hit-testable (`IsHitTestVisible="False"`) while
  folded, or maintain an off-tree clone that stays measured, and bind a
  `Grid.MinWidth` computed from `max(openContentDesiredWidth,
  foldedSummaryDesiredWidth) + leadingGutter + trailingGutter`. Build the
  masthead as a `Grid` (`Border Background="{ElevatedSurfaceBrush}"`) with
  columns `Auto,*,Auto,Auto` (leading accessory, title `TextBlock` with
  `TextTrimming="CharacterEllipsis"` — WinUI has no built-in "truncate
  middle" trimming, so port `truncates-title-in-middle` as a custom
  `IValueConverter`/behavior if fidelity to that exact truncation point
  matters — trailing accessory, then a `ToggleButton` restyled to a
  rotating chevron glyph for the disclosure control since WinUI has no
  dedicated disclosure-triangle bezel). Draw the corner badge as a
  `FontIcon`/`SymbolIcon` inside a `Grid` cell placed with `Margin` set to
  `-(badgeDiameter / 2 − cornerPeakInset)` on the top and right edges (which
  centers the badge on the corner's arc rather than its edge) and
  `HorizontalAlignment / VerticalAlignment="Right"/"Top"`, with
  `Canvas.ZIndex` (or simple
  z-order in the `Grid`'s children) set above the `Border` that draws the
  card's own `BorderBrush`/`BorderThickness`, matching
  `draws-badge-above-surface-border`.

