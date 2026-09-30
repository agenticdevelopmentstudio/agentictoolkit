<!-- leaf: implement-general-view-2/swatch-grid-view--part-2 · source: swatch-grid-view.md -->

# SwatchGridView — continued (part 2)

**Rules** (cite as `implement-general-view-2/swatch-grid-view--part-2#<slug>`):

- `decision` SHOULD — Leave the Role/trait accessibility bullet as an open question rather than assuming a specific role, and resolve the …

## Platform Notes

- **SwiftUI**: Chunk `colors` into rows of `columns` (or use
  `LazyVGrid` with `columns` repeated `GridItem(.fixed(swatchSize.width))`
  entries) inside a `VStack`/`LazyVGrid` with `spacing: spacing` on both
  axes; render each swatch as
  `RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: color)).frame(width:height:)`
  with an `.overlay(RoundedRectangle(cornerRadius: 3).stroke(borderColor, lineWidth: 0.5))`,
  where `borderColor` reads from the active theme/environment so it updates
  automatically on appearance change, unlike the fixed-fill quirk noted in
  Edge Cases.
- **Compose**: Chunk `colors` into rows inside a `Column` of `Row`s (or use
  `LazyVerticalGrid(columns = GridCells.Fixed(columns))`), each with
  `Arrangement.spacedBy(spacing.dp)`; render each swatch as a `Box` with
  `Modifier.size(swatchSize).clip(RoundedCornerShape(3.dp)).background(color).border(0.5.dp, borderColor, RoundedCornerShape(3.dp))`,
  binding `borderColor` to the current `MaterialTheme` so it recomposes on
  a theme change.
- **React/Web**: A CSS grid container
  (`display: grid; grid-template-columns: repeat(columns, swatchSizePx); gap: spacingPx`)
  whose children are one `<div>` per color, styled
  `border-radius: 3px; background-color: <color>; border: 0.5px solid var(--border-color)`,
  where `--border-color` is a CSS custom property the active theme
  updates, keeping the border reactive while the fill stays fixed to the
  color passed in, mirroring `renders-swatch-style`.
- **AppKit / UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/SwatchGridView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, inside
  the `ComposableSettings` namespace, conforming to `SettingsViewProtocol`.
  It composes a vertical `NSStackView` of horizontal `NSStackView` rows,
  each containing fixed-size, layer-backed plain `NSView` swatches, pinned
  to its own edges via `Self.pinToEdges`. There is no UIKit code path in
  source; a UIKit port has no direct `NSStackView`-of-`NSStackView`s
  equivalent and would instead use a `UICollectionView` with a
  `UICollectionViewFlowLayout` of fixed `itemSize == swatchSize` and
  `minimumInteritemSpacing`/`minimumLineSpacing == spacing`, with each cell
  drawing the same corner-radius/fill/border styling on its
  `contentView.layer`, and re-applying the border color on
  `traitCollectionDidChange(_:)` in place of `observeTheme`. Behind the
  Behavioral Requirements above: `columns` is clamped with
  `Swift.max(1, columns)`; the internal vertical stack view is the private
  `container` property, pinned via `Self.pinToEdges`; each swatch is a
  `wantsLayer`-backed plain `NSView` with `layer?.cornerRadius = 3`,
  `layer?.backgroundColor = color.cgColor`, and `layer?.borderWidth = 0.5`,
  with `layer?.borderColor` re-set on every theme change via `observeTheme`
  to `palette.nsColor(.border).cgColor`; `setColors(_:)` rebuilds by
  calling `container.arrangedSubviews.forEach { $0.removeFromSuperview() }`
  before re-adding rows built from the new array.
- **WinUI 3**: Bind an `ItemsRepeater` (or
  `ItemsControl`) using a `UniformGridLayout` — `MinItemWidth`/
  `MinItemHeight` set to `swatchSize`, `MinRowSpacing`/`MinColumnSpacing`
  set to `spacing` — to an `ObservableCollection<Color>` mirroring
  `colors`; the layout itself performs the row-wrapping
  `arranges-swatches-in-rows` does manually with `NSStackView`s. Give the
  `ItemsRepeater` an item template of a `Border` with
  `CornerRadius="3"`, `Width`/`Height` bound to `swatchSize`,
  `Background` bound through an `IValueConverter` from `Color` to
  `SolidColorBrush` (mirroring `layer.backgroundColor = color.cgColor`,
  fixed at bind time exactly like the source's fill), `BorderThickness="0.5"`,
  and `BorderBrush` bound to a theme resource such as
  `{ThemeResource CardStrokeColorDefaultBrush}`, which XAML re-resolves
  automatically on `ActualThemeChanged` — the WinUI analog of
  `observeTheme`'s live border repaint. Map `setColors(_:)` /
  `replaces-colors-and-rebuilds` to reassigning `ItemsRepeater.ItemsSource`
  to a new collection rather than mutating the existing one in place, since
  the source itself tears down and rebuilds every row/swatch on every
  update.

## Design Decisions

- **Decision**: Implement `setColors(_:)` by fully tearing down and
  rebuilding the row/swatch view hierarchy — removing every existing
  arranged subview before creating new rows — rather than reusing or
  diffing existing swatch views.
  **Rationale**: Source unconditionally clears the container's arranged
  subviews at the start of the shared rebuild routine used by both `init`
  and `setColors(_:)`. The only caller-observable contract is that
  `setColors(_:)` displays exactly the new colors afterward
  (**replaces-colors-and-rebuilds**); the full-rebuild strategy is how
  source achieves that, not itself a caller-visible requirement.
  **Approved**: pending
- **Decision**: Treat the swatch's border-repaints-on-theme-change /
  fill-fixed-at-creation asymmetry (see Edge Cases) as a documented quirk
  rather than a defect to silently correct in this recipe.
  **Rationale**: Source wraps only the border assignment in `observeTheme`;
  the background assignment in `makeSwatch(_:)` is a one-time
  `color.cgColor` write with no observer. The recipe describes this
  asymmetry as-is rather than assuming the fill should also be
  theme-reactive, since a data color (unlike a border) is not expected to
  shift with the theme.
  **Approved**: pending
- **Decision**: Leave the Role/trait accessibility bullet as an open
  question rather than assuming a specific role, and resolve the Label
  requirements bullet with a default SHOULD recommendation that review may
  override.
  **Rationale**: Source sets no accessibility API of any kind on
  `container`, its rows, or its swatches, and there is no comparable
  sibling row in
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/`
  that labels a color swatch for VoiceOver to pattern-match against.
  Recommending a default label (a caller-supplied name, falling back to a
  hex string) keeps the recipe implementable without inventing a role that
  source doesn't suggest.
  **Approved**: pending
