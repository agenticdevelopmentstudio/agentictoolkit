<!-- leaf: implement-general-view-2/swatch-grid-view · source: swatch-grid-view.md -->

**Rules** (cite as `implement-general-view-2/swatch-grid-view#<slug>`):

- `clamps-column-count` MUST
- `arranges-swatches-in-rows` MUST
- `builds-hierarchy-on-init` MUST
- `replaces-colors-and-rebuilds` MUST
- `pins-container-to-edges` MUST
- `uses-uniform-spacing` MUST
- `sizes-swatch-fixed` MUST
- `renders-swatch-style` MUST
- `traps-on-coder-init` MUST
- `renders-empty-grid` MUST
- `shortens-final-row` MUST
- `single-row-when-columns-exceeds-count` MUST
- `label-requirements` SHOULD — No swatch carries an accessibilityLabel or accessibilityValue describing the color it shows (e.g., a color name or hex …

# SwatchGridView

## Overview

`ComposableSettings.SwatchGridView` is an AppKit `NSView` from the
ComposableSettingsWindow system integration
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/SwatchGridView.swift`)
that displays a caller-supplied array of `NSColor` values as a grid of
fixed-size color swatches, wrapped into rows of a fixed column count. Per
its doc comment, it generalizes the ad-hoc swatch/ANSI grid the terminal
profiles view used to build inline. It conforms to `SettingsViewProtocol`.
Unlike sibling rows such as `ColorPickerView`, it is purely a display
component: it exposes one mutator, `setColors(_:)`, and contains no
target-action, control, or user-interaction code of any kind.

## Behavioral Requirements

- **clamps-column-count**: Component MUST clamp the initializer's `columns`
  parameter to a minimum of 1, so a caller-supplied value of 0 or a
  negative number never produces a zero- or negative-width row.
- **arranges-swatches-in-rows**: Component MUST lay out `colors` into
  consecutive rows of at most `columns` swatches each, filling each row in
  the order the colors appear in the array before starting the next row.
- **builds-hierarchy-on-init**: Component MUST build its full row/swatch
  view hierarchy once during initialization, from the `colors` and
  `columns` values supplied to that initializer.
- **replaces-colors-and-rebuilds**: Component MUST, when `setColors(_:)` is
  called, replace its stored `colors` with the supplied array and MUST
  display exactly the new colors afterward, with no swatch from the
  previous set remaining in the view hierarchy. See Design Decisions for
  the full-rebuild strategy source uses to satisfy this.
- **pins-container-to-edges**: Component MUST pin its internal vertical
  stack view to all four edges of itself with no additional constant.
- **uses-uniform-spacing**: Component MUST apply the single `spacing`
  initializer parameter as both the internal vertical stack view's
  row-to-row (vertical) spacing and each row's swatch-to-swatch
  (horizontal) spacing, so the gap between rows equals the gap between
  swatches within a row.
- **sizes-swatch-fixed**: Each swatch MUST be constrained to the
  constructor-supplied `swatchSize` width and height via activated layout
  constraints (default `CGSize(width: 22, height: 22)`), independent of the
  swatch's color content.
- **renders-swatch-style**: Each swatch MUST render with a 3pt corner
  radius, a background fill equal to the corresponding `NSColor` value, and
  a 0.5pt-wide border whose color is set, and re-set on every theme change,
  to the active theme's `.border` role color.
- **traps-on-coder-init**: Component MUST NOT support construction via
  `init(coder:)`; that initializer MUST trigger a fatal error.
- **renders-empty-grid**: Component MUST render zero rows when `colors` is
  empty, rather than trapping or throwing.
- **shortens-final-row**: Component MUST render a final row containing
  fewer than `columns` swatches when `colors.count` is not evenly divisible
  by `columns`.
- **single-row-when-columns-exceeds-count**: Component MUST render all
  colors in a single row shorter than `columns` when `columns` exceeds
  `colors.count`.

## Appearance

- **Corner radius**: `container` and `self` have no corner radius (neither
  sets `wantsLayer` nor a `cornerRadius`). Each individual swatch has a
  fixed 3pt corner radius (`swatch.layer?.cornerRadius = 3`), not
  configurable through any initializer parameter.
- **Padding**: `self` contributes 0pt of outer padding — `container` is
  pinned to all four edges with no additional constant. Internally, rows
  are spaced `spacing` apart vertically (`container.spacing`, default 4pt)
  and swatches within a row are spaced `spacing` apart horizontally
  (`row.spacing`, the same value), per `uses-uniform-spacing`.
- **Font**: Not applicable — the component draws no text; `NSStackView`
  rows and plain `NSView` swatches have no font property.
- **Background**: `self` and `container` have no background of their own
  (transparent; neither is layer-backed at that level). Each swatch's
  background is the corresponding `NSColor`'s `cgColor`, set once when the
  swatch is created in `makeSwatch(_:)` and never re-applied afterward
  except by a full rebuild (`init` or `setColors(_:)`) — see Edge Cases for
  the consequence for a dynamic/appearance-adaptive input color.
- **Foreground/Text**: Not applicable — no text or foreground-colored
  content exists anywhere in `SwatchGridView.swift`.
- **Border**: Each swatch has a 0.5pt border whose color is bound to the
  active theme's `.border` semantic role and kept live via `observeTheme`
  (see `renders-swatch-style`). Neither `container` nor `self` has a
  border.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  `SwatchGridView.swift`.
- **Min/Max size**: Not applicable at the grid level — no explicit min/max
  width or height constraint is set on `self` or `container`; the grid's
  overall size is the sum of its rows' intrinsic sizes. Each individual
  swatch, however, is fixed (not merely constrained a minimum) to
  `swatchSize` per `sizes-swatch-fixed`.

## Accessibility

- **Role/trait**: No `setAccessibilityRole`, `setAccessibilityElement`, or
  similar call appears anywhere in `SwatchGridView.swift`; `container`,
  each row, and each swatch are plain `NSStackView`/`NSView` instances with
  whatever default accessibility role AppKit assigns to an untouched
  `NSView` (effectively none). Whether the grid, its rows, or its swatches
  should be exposed to VoiceOver as discrete elements is an open design
  question that source does not answer.
- **Label requirements**: No swatch carries an `accessibilityLabel` or
  `accessibilityValue` describing the color it shows (e.g., a color name
  or hex value); a VoiceOver user landing on a swatch has no
  source-provided way to learn which color it represents. Default SHOULD,
  pending review: `makeSwatch(_:)` SHOULD call
  `setAccessibilityLabel(_:)` with a caller-supplied name for that color
  when one is available, falling back to a computed hex string (e.g.
  `#RRGGBB`) when no name is supplied. What would settle it: review
  approving this default, or specifying a different label format.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  the component has no loading state and never disables itself (see
  States); there is no state transition to announce.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven composition with no touch input path in source, and, per
  the States section, no interactive element exists at all to size a tap
  target for.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. Each swatch's 0.5pt border color resolves from the active theme's border role against the hosting background at runtime; the component performs no contrast check, so whether a given theme's resolved pair meets the 3:1 non-text contrast threshold cannot be determined from this file. This would be settled by a theme-level contrast audit of border against the backgrounds it sits on.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `colors` | `[NSColor]` | `[]` | The colors displayed, laid out row-major into fixed-width rows of `columns` swatches each. |
| `columns` | `Int` | `8` | Maximum swatches per row; clamped to a minimum of 1 (`clamps-column-count`). |
| `swatchSize` | `CGSize` | `CGSize(width: 22, height: 22)` | Fixed width/height applied to every swatch via layout constraints. |
| `spacing` | `CGFloat` | `4` | Applied uniformly as both the inter-row (vertical) gap and the inter-swatch (horizontal) gap within a row. |

## Accessibility Options

- **Reduce Motion**: Not applicable — source contains no animation,
  transition, or `NSAnimationContext` call; every rebuild replaces subviews
  instantaneously via `removeFromSuperview()`/`addArrangedSubview(_:)`.
- **Increase Contrast**: Not applicable to the swatch fill — the fill is
  the caller-supplied data color itself, not a themed UI color, so there is
  nothing for Increase Contrast to adjust without changing the data being
  displayed. The swatch border's color comes from the theme's `.border`
  semantic role (see **renders-swatch-style**); no separate Increase
  Contrast handling exists in `SwatchGridView.swift` itself.
- **Differentiate Without Color**: this component's entire purpose is
  conveying distinct colors as colors, with no accompanying label, pattern,
  or text differentiator in source — see **Label requirements** in
  Accessibility, which is the same gap that would let a Differentiate
  Without Color user distinguish swatches without relying on color
  perception alone.

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only renders the `NSColor` values it is constructed or
  updated with.
- **Storage**: Not applicable — source performs no read/write to disk,
  `UserDefaults`, or any other store.
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: Not applicable — the view retains `colors` and its own
  subviews only for its own lifetime; it persists nothing beyond that.

