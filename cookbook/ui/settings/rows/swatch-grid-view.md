---
id: f4740433-221c-4c89-b888-ee8da7aa4b3c
title: Swatch Grid View
domain: agentictoolkit://cookbook/ui/settings/rows/swatch-grid-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings-window component that displays an array of colors as
  a grid of fixed-size color swatches.
platforms:
- swift
- macos
tags:
- settings
- color
- grid
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/rows/color-picker-view
references: []
approved-by: ''
approved-date: ''
---

# Swatch Grid View

## Overview

The Swatch Grid View is a display component from the composable settings
window's system integration that displays a caller-supplied array of
colors as a grid of fixed-size color swatches, wrapped into rows of a
fixed column count. Per its doc comment, it generalizes the ad-hoc
swatch/ANSI grid the terminal profiles view used to build inline. Unlike
sibling rows such as the color picker row
(agentictoolkit://cookbook/ui/settings/rows/color-picker-view), it is
purely a display component: it exposes one mutator, a color-replacement
operation, and contains no interactive-control code of any kind.

## Behavioral Requirements

- **clamps-column-count**: Component MUST clamp the initializer's
  `columns` parameter to a minimum of 1, so a caller-supplied value of 0
  or a negative number never produces a zero- or negative-width row.
- **arranges-swatches-in-rows**: Component MUST lay out `colors` into
  consecutive rows of at most `columns` swatches each, filling each row
  in the order the colors appear in the array before starting the next
  row.
- **builds-hierarchy-on-init**: Component MUST build its full row/swatch
  view hierarchy once during initialization, from the `colors` and
  `columns` values supplied to that initializer.
- **replaces-colors-and-rebuilds**: Component MUST, when a new set of
  colors is supplied after construction, replace its stored colors with
  the supplied array and MUST display exactly the new colors afterward,
  with no swatch from the previous set remaining in the view hierarchy.
  See Design Decisions for the full-rebuild strategy source uses to
  satisfy this.
- **pins-container-to-edges**: Component MUST pin its internal container
  to all four edges of itself with no additional constant.
- **uses-uniform-spacing**: Component MUST apply the single `spacing`
  initializer parameter as both the internal container's row-to-row
  (vertical) spacing and each row's swatch-to-swatch (horizontal)
  spacing, so the gap between rows equals the gap between swatches
  within a row.
- **sizes-swatch-fixed**: Each swatch MUST be constrained to the
  constructor-supplied `swatchSize` width and height via activated
  layout constraints (default 22 by 22), independent of the swatch's
  color content.
- **renders-swatch-style**: Each swatch MUST render with a 3pt corner
  radius, a background fill equal to the corresponding color value, and
  a 0.5pt-wide border whose color is set, and re-set on every theme
  change, to the active theme's border role color.
- **renders-empty-grid**: Component MUST render zero rows when `colors`
  is empty, rather than trapping or throwing.
- **shortens-final-row**: Component MUST render a final row containing
  fewer than `columns` swatches when `colors.count` is not evenly
  divisible by `columns`.
- **single-row-when-columns-exceeds-count**: Component MUST render all
  colors in a single row shorter than `columns` when `columns` exceeds
  `colors.count`.

Construction requires its colors and layout parameters; the
deserializing construction path is rejected, a platform mechanic rather
than a normative requirement here — see traps-on-coder-init
under Platform Notes.

## Appearance

- **Corner radius**: The container and the component itself have no
  corner radius (neither is layer-backed with one at that level). Each
  individual swatch has a fixed 3pt corner radius, not configurable
  through any initializer parameter.
- **Padding**: The component contributes 0pt of outer padding — the
  container is pinned to all four edges with no additional constant.
  Internally, rows are spaced `spacing` apart vertically (default 4pt)
  and swatches within a row are spaced `spacing` apart horizontally (the
  same value), per uses-uniform-spacing.
- **Font**: Not applicable — the component draws no text; its rows and
  swatches have no font property.
- **Background**: The component and its container have no background of
  their own (transparent; neither is layer-backed at that level). Each
  swatch's background is the corresponding color's fill, set once when
  the swatch is created and never re-applied afterward except by a full
  rebuild (construction or a color replacement) — see Edge Cases for the
  consequence for a dynamic/appearance-adaptive input color.
- **Foreground/Text**: Not applicable — no text or foreground-colored
  content exists anywhere in source.
- **Border**: Each swatch has a 0.5pt border whose color is bound to the
  active theme's border semantic role and kept live on a theme change
  (see renders-swatch-style). Neither the container nor the component
  itself has a border.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere
  in source.
- **Min/Max size**: Not applicable at the grid level — no explicit
  min/max width or height constraint is set on the component or its
  container; the grid's overall size is the sum of its rows' intrinsic
  sizes. Each individual swatch, however, is fixed (not merely
  constrained a minimum) to its configured size per sizes-swatch-fixed.

## States

| State | Appearance change |
|-------|------------------|
| Default | Swatches render in rows per colors/columns; empty colors renders zero rows. |
| Pressed | Not applicable: no interactive control or click-handling code exists anywhere in source; swatches and rows are plain, non-interactive elements. |
| Disabled | Not applicable: an enabled state is never referenced in source; the component has no notion of an enabled/disabled state. |
| Focused | Not applicable: the component overrides no focus-related property and contains no interactive control, so it never becomes first responder or shows a focus ring. |
| Loading | Not applicable: every operation in source (rebuilding, swatch creation, color replacement) is a synchronous property assignment; there is no asynchronous operation and no loading indicator. |

## Accessibility

- **Role/trait**: No explicit accessibility-role call appears anywhere
  in source; the container, each row, and each swatch are plain elements
  with whatever default accessibility role the platform assigns to an
  untouched view (effectively none). Whether the grid, its rows, or its
  swatches should be exposed to assistive technology as discrete
  elements is an open design question that source does not answer.
- **Label requirements**: No swatch carries an accessible name or value
  describing the color it shows (e.g., a color name or hex value); a
  screen reader user landing on a swatch has no source-provided way to
  learn which color it represents. Default SHOULD, pending review:
  swatch construction SHOULD assign an accessible label using a
  caller-supplied name for that color when one is available, falling
  back to a computed hex string (e.g. `#RRGGBB`) when no name is
  supplied. What would settle it: review approving this default, or
  specifying a different label format.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  the component has no loading state and never disables itself (see
  States); there is no state transition to announce.
- **Minimum tap target**: Not applicable — this is a pointer/
  trackpad-driven composition with no touch input path in source, and,
  per the States section, no interactive element exists at all to size a
  tap target for.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source.
  Each swatch's 0.5pt border color resolves from the active theme's
  border role against the hosting background at runtime; the component
  performs no contrast check, so whether a given theme's resolved pair
  meets the 3:1 non-text contrast threshold cannot be determined from
  this file. This would be settled by a theme-level contrast audit of
  border against the backgrounds it sits on.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| swatch-grid-view-001 | clamps-column-count | Construct with columns = 0 | The component lays out swatches into rows of at most 1 swatch each (columns treated as 1) |
| swatch-grid-view-002 | clamps-column-count | Construct with columns = -3 | The component lays out swatches into rows of at most 1 swatch each (columns treated as 1) |
| swatch-grid-view-003 | arranges-swatches-in-rows | Construct with 10 colors and columns = 4 | 3 rows are produced: 4, 4, and 2 swatches, in the same order as the input array |
| swatch-grid-view-004 | builds-hierarchy-on-init | Construct with 3 colors and columns = 8 | Immediately after construction, the row/swatch hierarchy contains exactly 1 row with exactly 3 swatches |
| swatch-grid-view-005 | replaces-colors-and-rebuilds | Construct with 5 colors, then replace them with an empty array | The row/swatch hierarchy is empty (0 rows, 0 swatches) after the call; none of the original 5 swatch elements remain anywhere in it |
| swatch-grid-view-006 | replaces-colors-and-rebuilds | Construct with 2 colors, then replace them with 6 new colors, columns unchanged at 8 | The row/swatch hierarchy contains exactly 1 row with exactly 6 swatches, none of which are the original 2 swatch instances |
| swatch-grid-view-007 | pins-container-to-edges | Construct the component and inspect its internal container's constraints | That container's top/leading/trailing/bottom anchors are each constrained equal to the corresponding anchor of the component, with no constant offset |
| swatch-grid-view-008 | uses-uniform-spacing | Construct with spacing = 10 | The internal container's spacing and every row's spacing each equal 10 |
| swatch-grid-view-009 | sizes-swatch-fixed | Construct with a swatch size of 40 by 16 and 1 color | The resulting swatch has an active width constraint of 40 and an active height constraint of 16 |
| swatch-grid-view-010 | renders-swatch-style | Construct with 1 color and inspect the resulting swatch's layer | The swatch is layer-backed with a 3pt corner radius, a background equal to the color's fill, and a border width of 0.5 |
| swatch-grid-view-011 | renders-swatch-style | Construct with 1 color, then switch the active theme from one built-in theme (e.g. a dark theme) to another | The swatch's border color changes from the old theme's border role color to the new theme's border role color; the fill is unaffected |
| swatch-grid-view-013 | renders-empty-grid | Construct with an empty color array | The view has zero rows and zero swatches immediately after construction |
| swatch-grid-view-014 | shortens-final-row | Construct with 10 colors and columns = 4 | The final row contains exactly 2 swatches (10 mod 4), fewer than a full row of 4 |
| swatch-grid-view-015 | single-row-when-columns-exceeds-count | Construct with 3 colors and columns = 8 | Exactly 1 row is produced, containing all 3 swatches, fewer than columns |

## Edge Cases

- Null/empty input: colors defaults to an empty array and is a
  non-optional array. When empty, the row-building loop never executes,
  so the view ends up with zero rows and zero swatches — the
  **renders-empty-grid** requirement.
- Boundary values — colors count not evenly divisible by columns: the
  last row contains `colors.count % columns` swatches rather than a full
  `columns` — the **shortens-final-row** requirement, directly
  traceable to the row-building loop's bounds.
- Boundary values — `columns` exceeding `colors.count`: all colors
  render in a single row shorter than `columns` — the
  **single-row-when-columns-exceeds-count** requirement, following from
  the same loop bounds as above.
- Concurrent access: Not applicable — the component is confined to the
  UI thread, so all access to colors, the container, and every mutating
  method is serialized; there is no code path by which two threads
  mutate the view simultaneously.
- Error states: Not applicable — every operation in source (property
  assignment, layer configuration, constraint activation) is synchronous
  and non-throwing; no error-producing API appears in source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only renders caller-supplied color values.
- Dynamic/appearance-adaptive input color: swatch construction sets the
  swatch's fill to the supplied color once, at creation time, and never
  revisits that assignment. Only the swatch's *border* color is
  re-applied on a theme change. If a caller passes a dynamic
  (appearance-adaptive) color as a swatch color, the swatch's fill MAY
  remain visually stale after a system appearance change until the
  caller triggers a full rebuild by replacing the colors again; this is
  current, source-traceable behavior — not a named MUST requirement —
  and is recorded as a documented quirk in Design Decisions rather than
  corrected here.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `colors` | array of colors | `[]` | The colors displayed, laid out row-major into fixed-width rows of `columns` swatches each. |
| `columns` | integer | `8` | Maximum swatches per row; clamped to a minimum of 1 (`clamps-column-count`). |
| `swatchSize` | size (width/height) | 22 by 22 | Fixed width/height applied to every swatch via layout constraints. |
| `spacing` | number | `4` | Applied uniformly as both the inter-row (vertical) gap and the inter-swatch (horizontal) gap within a row. |

## Deep Linking

Not applicable: this component is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link
handler appears anywhere in source.

## Localization

Not applicable: the file contains no user-facing string literals of any
kind. `colors` is structured color data supplied by the caller, not a
localizable string.

## Accessibility Options

- **Reduce Motion**: Not applicable — source contains no animation or
  transition call; every rebuild replaces subviews instantaneously.
- **Increase Contrast**: Not applicable to the swatch fill — the fill is
  the caller-supplied data color itself, not a themed UI color, so there
  is nothing for Increase Contrast to adjust without changing the data
  being displayed. The swatch border's color comes from the theme's
  border semantic role (see **renders-swatch-style**); no separate
  Increase Contrast handling exists in source itself.
- **Differentiate Without Color**: this component's entire purpose is
  conveying distinct colors as colors, with no accompanying label,
  pattern, or text differentiator in source — see **Label requirements**
  in Accessibility, which is the same gap that would let a
  Differentiate Without Color user distinguish swatches without relying
  on color perception alone.

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears
anywhere in source; the grid always renders once constructed.

## Analytics

Not applicable: source contains no analytics or telemetry call.

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only renders the color values it is constructed or
  updated with.
- **Storage**: Not applicable — source performs no read/write to disk or
  any other store.
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: Not applicable — the view retains its colors and its
  own subviews only for its own lifetime; it persists nothing beyond
  that.

## Logging

Not applicable: source contains no logging call (no print, log, or
logger reference anywhere in source).

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
  to its own edges via `Self.pinToEdges`. It supports construction only
  through its designated initializer: `init(coder:)` triggers a fatal
  error rather than producing an instance (traps-on-coder-init) — a fatal
  trap cannot be caught inside the normal test process, so verifying this
  requires a subprocess/death-test harness, and has no analogue on
  platforms without a coder-based initializer. There is no UIKit code
  path in source; a UIKit port has no direct `NSStackView`-of-
  `NSStackView`s equivalent and would instead use a `UICollectionView`
  with a `UICollectionViewFlowLayout` of fixed `itemSize == swatchSize`
  and `minimumInteritemSpacing`/`minimumLineSpacing == spacing`, with each
  cell drawing the same corner-radius/fill/border styling on its
  `contentView.layer`, and re-applying the border color on
  `traitCollectionDidChange(_:)` in place of `observeTheme`. Behind the
  Behavioral Requirements above: `columns` is clamped with
  `Swift.max(1, columns)`; the internal vertical stack view is the private
  `container` property, pinned via `Self.pinToEdges`; each swatch is a
  `wantsLayer`-backed plain `NSView` with `layer?.cornerRadius = 3`,
  `layer?.backgroundColor = color.cgColor`, and `layer?.borderWidth = 0.5`,
  with `layer?.borderColor` re-set on every theme change via `observeTheme`
  to `palette.nsColor(.border).cgColor`; the color-replacement operation
  rebuilds by calling
  `container.arrangedSubviews.forEach { $0.removeFromSuperview() }` before
  re-adding rows built from the new array.
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
  `observeTheme`'s live border repaint. Map the color-replacement
  operation / `replaces-colors-and-rebuilds` to reassigning
  `ItemsRepeater.ItemsSource` to a new collection rather than mutating the
  existing one in place, since the source itself tears down and rebuilds
  every row/swatch on every update.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/SwatchGridView.swift` |

## Design Decisions

- **Decision**: Implement the color-replacement operation by fully
  tearing down and rebuilding the row/swatch view hierarchy — removing
  every existing arranged element before creating new rows — rather than
  reusing or diffing existing swatch views.
  **Rationale**: Source unconditionally clears the container's arranged
  elements at the start of the shared rebuild routine used by both
  construction and color replacement. The only caller-observable
  contract is that replacing the colors displays exactly the new colors
  afterward (**replaces-colors-and-rebuilds**); the full-rebuild
  strategy is how source achieves that, not itself a caller-visible
  requirement.
  **Approved**: pending
- **Decision**: Treat the swatch's border-repaints-on-theme-change /
  fill-fixed-at-creation asymmetry (see Edge Cases) as a documented quirk
  rather than a defect to silently correct in this recipe.
  **Rationale**: Source re-applies only the border color on a theme
  change; the fill assignment at swatch-creation time is a one-time
  write with no observer. The recipe describes this asymmetry as-is
  rather than assuming the fill should also be theme-reactive, since a
  data color (unlike a border) is not expected to shift with the theme.
  **Approved**: pending
- **Decision**: Leave the Role/trait accessibility bullet as an open
  question rather than assuming a specific role, and resolve the Label
  requirements bullet with a default SHOULD recommendation that review
  may override.
  **Rationale**: Source sets no accessibility API of any kind on the
  container, its rows, or its swatches, and there is no comparable
  sibling row in the same source directory that labels a color swatch
  for a screen reader to pattern-match against. Recommending a default
  label (a caller-supplied name, falling back to a hex string) keeps the
  recipe implementable without inventing a role that source doesn't
  suggest.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | failed | accessibility |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

Statuses rest on: `SwatchGridView.swift` uses only native
`NSStackView`/`NSView` composition with no business logic mixed into its
rendering code, but defines no accessibility label or non-color
differentiator on any swatch.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial ingredient recipe for SwatchGridView, covering row-wrapping layout, full-rebuild update strategy, theme-reactive swatch border vs. fixed fill, and two open accessibility questions (role and per-swatch label) for review. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: moved AppKit implementation identifiers out of Behavioral Requirements into Platform Notes; relaxed replaces-colors-and-rebuilds and recorded the rebuild strategy as a Design Decision; reframed the fixed-fill edge case as current MAY behavior and dropped the unsupported Increase Contrast claim; removed the requirement-count Design Decision and reformatted Design Decisions to the bold Decision/Rationale/Approved form; promoted three Edge Case MUSTs to named requirements with test vectors; rephrased test vectors 004-007 and 011-012 to observable structure, a named theme-change mechanism, and a death-test note; added a default SHOULD recommendation for swatch accessibility labels; fixed Platform Notes formatting, shortened the summary, and cleaned up the Compliance table; records the unverified theme-token contrast as an open question. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/rows/. |
