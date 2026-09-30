<!-- leaf: implement-panel/view--part-2 · source: panel-view.md -->

# PanelView — continued (part 2)

## Platform Notes

- **SwiftUI**: Compose a `VStack(alignment: .leading, spacing: 20)` inside a
  container padded `.padding(.top, 20).padding(.horizontal, 20)`, with the
  bottom left to the stack's own intrinsic height rather than a fixed
  `.padding(.bottom, 20)` pin — SwiftUI's default layout already lets
  content fall short of an oversized parent, mirroring
  **bottom-inset-inequality**. Give the container a `.background` filled
  from the theme's window-background token, matching
  **construction-time-background-paint**/**theme-change-background-repaint**,
  which SwiftUI's environment-driven color already repaints automatically
  on a theme change with no manual observer. Insert an extra
  `Spacer().frame(height: 10)` immediately before a heading view — 10pt
  plus the `VStack`'s own 20pt `spacing` totals the 30pt of **heading-gap**
  — but only when a view already precedes it, mirroring
  **empty-stack-spacing-skip**.
- **Compose**: Use a `Column(verticalArrangement =
  Arrangement.spacedBy(20.dp), horizontalAlignment = Alignment.Start,
  modifier = Modifier.padding(start = 20.dp, end = 20.dp, top =
  20.dp).background(<windowBackground token>))`, letting the column wrap its
  content height rather than filling a fixed-height parent, the Compose
  analog of the inequality bottom constraint. Precede a heading composable
  with an extra `Spacer(Modifier.height(10.dp))` (10dp + the column's own
  20dp gap = 30dp) only when it is not the column's first child, mirroring
  **heading-gap**/**empty-stack-spacing-skip**.
- **React/Web**: A `<div>` styled `display: flex; flex-direction: column;
  align-items: flex-start; gap: 20px; padding: 20px 20px 0 20px;
  background: var(--window-background)`, sized to its content rather than a
  fixed height so it can fall short of a taller parent, mirroring
  **bottom-inset-inequality**. Give a heading element `margin-top: 10px` in
  addition to the flex `gap` (10px + 20px = 30px total) only when a previous
  sibling exists (a `:not(:first-child)` selector), mirroring the
  conditional spacing rule; rely on the CSS custom property's own value
  updating on a theme class/attribute change for
  **theme-change-background-repaint**.
- **AppKit / UIKit** (source platform): A macOS-only (`import AppKit`)
  `open`, `@MainActor` `NSView` subclass inside the `ComposableSettings`
  namespace (see Overview for the source file and its layout/theme
  dependencies), built on `NSStackView` and Auto Layout. Internally, the
  private stored properties `stackView` (`NSStackView`) and `themeObserver`
  (`ThemePaletteObserver?`) back the stack and theme-repaint behavior
  described under Behavioral Requirements. There is no UIKit code path in
  source; because `ThemePaletteObserver` itself is already cross-platform
  (`SourcesUI/Shared`), a UIKit port would only need to replace
  `NSStackView` with `UIStackView` and the layer background assignment with
  the UIKit equivalent (`layer.backgroundColor` on a layer-backed `UIView`,
  which is layer-backed by default) — the theme observer and its
  notification-driven repaint carry over unchanged.
- **WinUI 3**: Build a `StackPanel` (`Orientation="Vertical"`,
  `Spacing="20"`, matching **group-spacing**) inside a root whose
  `Background="{ThemeResource ApplicationPageBackgroundThemeBrush}"` (or the
  app's own window-background resource) repaints automatically through
  WinUI's `ThemeResource` re-resolution on a `RequestedTheme` change — the
  platform-native analog of
  **construction-time-background-paint**/**theme-change-background-repaint**,
  needing no manual observer equivalent to `ThemePaletteObserver`. Give the
  root `Padding="20,20,20,0"` and leave the `StackPanel`'s
  `VerticalAlignment` at its default `Top` rather than `Stretch`, so it
  sizes to its content and leaves slack below rather than stretching to
  fill the container — the WinUI analog of **bottom-inset-inequality**.
  Because `StackPanel.Spacing` cannot vary per-gap the way
  `NSStackView.setCustomSpacing(after:)` can, reproduce
  **heading-gap**/**empty-stack-spacing-skip** with an extra `<Border
  Height="10"/>` spacer element inserted immediately before a heading
  `TextBlock`/`StackPanel` — 10 plus the panel's own 20 `Spacing` totals the
  30 of `groupSpacing * 1.5` — but only when `Children.Count > 0` at the
  point of insertion.

## Design Decisions

- **Decision**: Constrain the internal stack view's bottom anchor with
  `lessThanOrEqualTo` rather than an equality constraint, unlike the
  top/leading/trailing edges.
  **Rationale**: Not explained in source comments beyond the code itself.
  An inequality lets the stack's own Auto-Layout-computed height determine
  the panel's occupied region without forcing the stack to stretch and fill
  a taller frame the panel happens to be given, the same "size to content,
  not to container" outcome `GroupView`'s sibling recipe gets from having no
  height constraint of its own at all.
  **Approved**: pending
- **Decision**: The designated `init(frame:)` ignores the caller-supplied
  `frameRect` entirely and always forwards `.zero` to `super.init(frame:)`.
  **Rationale**: Not explained in source comments; the effect is that no
  caller can give a `PanelView` a non-zero initial frame, even by bypassing
  the `init()` convenience initializer. This is a known quirk rather than a
  deliberate API contract — kept as-is because it is what the source does
  (see **zero-argument-convenience-initializer** and the frame edge case
  above).
  **Approved**: pending
- **Decision**: Resolve the background color through `ThemePaletteObserver(
  host: self)` rather than reading `ThemePaletteObserver.currentPalette`
  (the unscoped, app-wide answer) once at construction.
  **Rationale**: Per the source's own comment, this keeps the panel's
  ground the same as "the sidebar and the window," painted from `self`'s
  own resolved `ThemeScope` rather than a single global palette, and it
  stays live for the view's lifetime rather than being captured once.
  **Approved**: pending
- **Decision**: `addHeading` widens the gap above a heading to
  `groupSpacing * 1.5` only when a prior arranged subview already exists,
  rather than always applying the wider spacing or applying it to the gap
  below the heading.
  **Rationale**: Per the source's own doc comment, "the gap above a heading
  is wider than the gap between two cards, because that gap is what says
  the heading belongs to what comes *after* it — at the stack's own spacing
  it reads as a caption trailing the card above." A first heading with
  nothing above it needs no such signal, so no adjustment is made.
  **Approved**: pending
- **Decision**: `required init?(coder:)` traps via `fatalError`, and its
  current message text (`not overridden`) is left as-is rather than
  standardized to match the sibling `GroupView`/`PanelHeadingView` message
  (`init(coder:) has not been implemented`).
  **Rationale**: The message text is not part of the
  **coder-initializer-rejection** requirement; the mismatch is a real,
  source-traceable inconsistency between siblings, not smoothed over in
  either direction.
  **Approved**: pending
