---
id: f4740433-221c-4c89-b888-ee8da7aa4b3c
title: SwatchGridView
domain: agentictoolkit://recipes/swatch-grid-view
type: ingredient
version: 1.1.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS ComposableSettings NSView that displays an array of NSColor
  values as a grid of fixed-size color swatches.
platforms:
- swift
- macos
tags:
- settings
- color
- grid
- macos
- appkit
depends-on: []
related:
- agentictoolkit://recipes/color-picker-view
references: []
approved-by: ''
approved-date: ''
---

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

## States

| State | Appearance change |
|-------|------------------|
| Default | Swatches render in rows per `colors`/`columns`; empty `colors` renders zero rows. |
| Pressed | Not applicable: no `NSControl`, target-action, or click-handling code exists anywhere in `SwatchGridView.swift`; swatches and rows are plain, non-interactive `NSView`/`NSStackView` instances. |
| Disabled | Not applicable: `isEnabled` is never referenced in source; the component has no notion of an enabled/disabled state. |
| Focused | Not applicable: the component overrides no focus-related property and contains no `NSControl`, so it never becomes first responder or shows a focus ring. |
| Loading | Not applicable: every operation in source (`rebuild()`, `makeSwatch(_:)`, `setColors(_:)`) is a synchronous property assignment; there is no asynchronous operation and no loading indicator. |

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

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| swatch-grid-view-001 | clamps-column-count | Construct with `columns: 0` | The component lays out swatches into rows of at most 1 swatch each (columns treated as 1) |
| swatch-grid-view-002 | clamps-column-count | Construct with `columns: -3` | The component lays out swatches into rows of at most 1 swatch each (columns treated as 1) |
| swatch-grid-view-003 | arranges-swatches-in-rows | Construct with 10 colors and `columns: 4` | 3 rows are produced: 4, 4, and 2 swatches, in the same order as the input array |
| swatch-grid-view-004 | builds-hierarchy-on-init | Construct with 3 colors and `columns: 8` | Immediately after `init` returns, the view's row/swatch hierarchy contains exactly 1 row with exactly 3 swatches |
| swatch-grid-view-005 | replaces-colors-and-rebuilds | Construct with 5 colors, then call `setColors([])` | The view's row/swatch hierarchy is empty (0 rows, 0 swatches) after the call; none of the original 5 swatch views remain anywhere in it |
| swatch-grid-view-006 | replaces-colors-and-rebuilds | Construct with 2 colors, then call `setColors(_:)` with 6 new colors and `columns` unchanged at 8 | The view's row/swatch hierarchy contains exactly 1 row with exactly 6 swatches, none of which are the original 2 swatch view instances |
| swatch-grid-view-007 | pins-container-to-edges | Construct the component and inspect its internal stack view's constraints (found among `self.subviews`) | That stack view's top/leading/trailing/bottom anchors are each constrained equal to the corresponding anchor of `self`, with no constant offset |
| swatch-grid-view-008 | uses-uniform-spacing | Construct with `spacing: 10` | The internal stack view's spacing and every row's spacing each equal 10 |
| swatch-grid-view-009 | sizes-swatch-fixed | Construct with `swatchSize: CGSize(width: 40, height: 16)` and 1 color | The resulting swatch view has an active width constraint of 40 and an active height constraint of 16 |
| swatch-grid-view-010 | renders-swatch-style | Construct with 1 color and inspect the resulting swatch's layer | `wantsLayer == true`, `layer.cornerRadius == 3`, `layer.backgroundColor == color.cgColor`, `layer.borderWidth == 0.5` |
| swatch-grid-view-011 | renders-swatch-style | Construct with 1 color, then call `ThemeManager.selectTheme(id:)` to switch the shared `ThemeManager` from one built-in theme (e.g. `solarizedDark`) to another (e.g. `dracula`) | The swatch's `layer.borderColor` changes from the old theme's `.border` role color to the new theme's `.border` role color; `layer.backgroundColor` (the fill) is unaffected |
| swatch-grid-view-012 | traps-on-coder-init | Attempt `SwatchGridView(coder: someCoder)` | The call traps with a fatal error; no instance is returned. AppKit-specific: a fatal trap cannot be caught inside the normal test process, so this requires a subprocess/death-test harness, and has no analogue on platforms without a coder-based initializer. |
| swatch-grid-view-013 | renders-empty-grid | Construct with `colors: []` | The view has zero rows and zero swatches immediately after `init` returns |
| swatch-grid-view-014 | shortens-final-row | Construct with 10 colors and `columns: 4` | The final row contains exactly 2 swatches (`10 % 4`), fewer than a full row of 4 |
| swatch-grid-view-015 | single-row-when-columns-exceeds-count | Construct with 3 colors and `columns: 8` | Exactly 1 row is produced, containing all 3 swatches, fewer than `columns` |

## Edge Cases

- Null/empty input: `colors` defaults to `[]` and is a non-optional
  `[NSColor]`. When empty, the row-building loop never executes, so the
  view ends up with zero rows and zero swatches — the **renders-empty-grid**
  requirement.
- Boundary values — colors count not evenly divisible by columns: the last
  row contains `colors.count % columns` swatches rather than a full
  `columns` — the **shortens-final-row** requirement, directly traceable to
  the row-building loop's bounds.
- Boundary values — `columns` exceeding `colors.count`: all colors render
  in a single row shorter than `columns` — the
  **single-row-when-columns-exceeds-count** requirement, following from
  the same loop bounds as above.
- Concurrent access: Not applicable — the class is `@MainActor`-isolated,
  so Swift's concurrency checker serializes all access to `colors`,
  `container`, and every mutating method; there is no code path by which
  two threads mutate the view simultaneously.
- Error states: Not applicable — every operation in `SwatchGridView.swift`
  (property assignment, layer configuration, constraint activation) is
  synchronous and non-throwing; no `try`, `Result`, or error-producing API
  appears in source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only renders caller-supplied `NSColor` values.
- Dynamic/appearance-adaptive input color: `makeSwatch(_:)` sets the
  swatch's `backgroundColor` to `color.cgColor` once, at swatch-creation
  time, and never revisits that assignment. Only the swatch's *border*
  color is re-applied on a theme change, via `observeTheme`. If a caller
  passes a dynamic (appearance-adaptive) `NSColor` as a swatch color, the
  swatch's fill MAY remain visually stale after a system appearance change
  until the caller triggers a full rebuild by calling `setColors(_:)`
  again; this is current, source-traceable behavior — not a named MUST
  requirement — and is recorded as a documented quirk in Design Decisions
  rather than corrected here.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `colors` | `[NSColor]` | `[]` | The colors displayed, laid out row-major into fixed-width rows of `columns` swatches each. |
| `columns` | `Int` | `8` | Maximum swatches per row; clamped to a minimum of 1 (`clamps-column-count`). |
| `swatchSize` | `CGSize` | `CGSize(width: 22, height: 22)` | Fixed width/height applied to every swatch via layout constraints. |
| `spacing` | `CGFloat` | `4` | Applied uniformly as both the inter-row (vertical) gap and the inter-swatch (horizontal) gap within a row. |

## Deep Linking

Not applicable: `SwatchGridView` is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
appears anywhere in `SwatchGridView.swift`.

## Localization

Not applicable: the file contains no user-facing string literals of any
kind — no `Text`, `NSTextField`, or similar. `colors` is structured
`NSColor` data supplied by the caller, not a localizable string.

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

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears
anywhere in `SwatchGridView.swift`; the grid always renders once
constructed.

## Analytics

Not applicable: `SwatchGridView.swift` contains no analytics or telemetry
call.

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

## Logging

Not applicable: `SwatchGridView.swift` contains no logging call (no
`print`, `os_log`, or logger reference anywhere in source).

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
