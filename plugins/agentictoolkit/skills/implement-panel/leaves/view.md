<!-- leaf: implement-panel/view · source: panel-view.md -->

**Rules** (cite as `implement-panel/view#<slug>`):

- `settings-view-conformance` MUST
- `main-actor-confinement` MUST
- `zero-argument-convenience-initializer` MUST
- `self-autoresizing-mask` MUST
- `layer-backing` MUST
- `vertical-leading-stack-alignment` MUST
- `group-spacing` MUST
- `stack-autoresizing-mask` MUST
- `top-leading-trailing-inset` MUST
- `bottom-inset-inequality` MUST
- `construction-time-background-paint` MUST
- `theme-change-background-repaint` MUST
- `theme-observer-retention` MUST
- `coder-initializer-rejection` MUST
- `group-arranged-subview-append` MUST
- `heading-construction` MUST
- `heading-caption-default` MUST
- `heading-gap` MUST
- `empty-stack-spacing-skip` MUST
- `heading-arranged-subview-append` MUST
- `heading-width-match` MUST
- `heading-return` MUST
- `min-max-size` MAY — None declared by PanelView itself. Its width is whatever its superview gives it (no self-width constraint is set here, …

# PanelView

## Overview

`ComposableSettings.PanelView`, at
`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PanelView.swift`,
is the root container for a `ComposableSettings` panel: an `open`, `@MainActor`
`NSView` subclass conforming to `SettingsViewProtocol` that hosts a vertical
stack of `GroupView` cards, spaced apart inside the panel's content area, per
the source's own doc comment. It owns a single internal `NSStackView` inset
from its own edges by the panel's outer margin, paints its own layer
background from the active theme, and exposes exactly two mutating calls:
`addGroup(_:)`, which appends a `GroupView` card, and `addHeading(_:
caption:)`, which appends a `PanelHeadingView` (constructed internally) ahead
of the groups that follow it, widening the gap above it so the heading reads
as belonging to what comes after it rather than as a caption trailing the
card above — per the source's own comment on `addHeading`. Both `GroupView`
and `PanelHeadingView` are separate components with their own recipes; this
recipe covers only what `PanelView.swift` itself does with them. The
background color is resolved through a `ThemePaletteObserver` (from the
`agenticdevelopertoolkit` submodule's `ThemeBinding.swift`), created with
`host: self` so the color tracks `PanelView`'s own resolved `ThemeScope`
rather than the app-wide default; the source's own comment on that call
explains the choice of color: "The same ground as the sidebar and the
window: the cards are what stand out here, and a panel-shaped patch of a
second near-identical colour behind them only reads as a misprint."

## Behavioral Requirements

- **settings-view-conformance**: The component MUST conform to
  `SettingsViewProtocol`.
- **main-actor-confinement**: The component MUST be usable only on the main
  actor; the class is declared `@MainActor`.
- **zero-argument-convenience-initializer**: The `public convenience
  init()` MUST forward to `init(frame: .zero)` with no parameters of its own.
- **self-autoresizing-mask**: The component MUST set
  `translatesAutoresizingMaskIntoConstraints = false` on itself at
  construction.
- **layer-backing**: The component MUST set `wantsLayer = true` at
  construction.
- **vertical-leading-stack-alignment**: The component MUST construct an
  internal vertical stack view with `orientation == .vertical` and
  `alignment == .leading`.
- **group-spacing**: The component MUST set the internal stack view's
  `spacing` to `SettingsLayout.default[.groupSpacing]` (20pt).
- **stack-autoresizing-mask**: The component MUST set
  `translatesAutoresizingMaskIntoConstraints = false` on the internal stack
  view.
- **top-leading-trailing-inset**: The component MUST pin the internal stack
  view's top, leading, and trailing anchors to its own corresponding
  anchors, each offset by `SettingsLayout.default[.panelInset]` (20pt)
  inward.
- **bottom-inset-inequality**: The component MUST constrain the internal
  stack view's bottom anchor `lessThanOrEqualTo` its own bottom anchor,
  offset by `-SettingsLayout.default[.panelInset]` (20pt) — an inequality,
  not an equality constraint.
- **construction-time-background-paint**: The component MUST set
  `layer?.backgroundColor` to the current theme's `.windowBackground` role
  (`palette.windowBackgroundColor.cgColor`), resolved through a
  `ThemePaletteObserver` constructed with `host: self`, immediately at
  construction.
- **theme-change-background-repaint**: The component MUST update
  `layer?.backgroundColor` to the new theme's `.windowBackground` role every
  time the active theme changes or the view's resolved `ThemeScope` changes,
  for the lifetime of the view (`ThemePaletteObserver`'s own notification
  subscriptions).
- **theme-observer-retention**: The component MUST hold its
  `ThemePaletteObserver` in a stored property for as long as the view
  exists, so the observer's Combine subscriptions are not deallocated
  early.
- **coder-initializer-rejection**: `required init?(coder: NSCoder)` MUST
  trap via `fatalError` when invoked; the exact message text is not part of
  this requirement (see Design Decisions).
- **group-arranged-subview-append**: `addGroup(_:)` MUST add the given
  `GroupView` as the next arranged subview of the internal stack view, with
  no other transformation.
- **heading-construction**: `addHeading(_:caption:)` MUST construct a
  `PanelHeadingView(title:caption:)` from its own `title` and `caption`
  parameters.
- **heading-caption-default**: `addHeading(_:caption:)` MUST default its
  `caption` parameter to `nil` when the caller omits it.
- **heading-gap**: When the internal stack view already has at least one
  arranged subview at the time `addHeading` is called, the component MUST
  set its custom spacing after that existing last arranged subview to
  `SettingsLayout.default[.groupSpacing] * 1.5` (30pt), before adding the
  new heading.
- **empty-stack-spacing-skip**: When the internal stack view has no
  arranged subviews at the time `addHeading` is called, the component MUST
  NOT attempt to set any custom spacing (there is no prior arranged subview
  to set it after).
- **heading-arranged-subview-append**: `addHeading(_:caption:)` MUST add
  the constructed `PanelHeadingView` as the next arranged subview of the
  internal stack view, after any spacing adjustment above has been made.
- **heading-width-match**: `addHeading(_:caption:)` MUST activate a
  constraint equating the constructed heading's `widthAnchor` to the
  internal stack view's `widthAnchor`.
- **heading-return**: `addHeading(_:caption:)` MUST return the constructed
  `PanelHeadingView` to its caller; the method is marked
  `@discardableResult`.

## Appearance

- **Corner radius**: Not applicable — `PanelView.swift` never sets
  `layer?.cornerRadius`; `wantsLayer = true` is set only so a background
  color can be painted on the layer.
- **Padding**: `stackView` is inset `SettingsLayout.default[.panelInset]` =
  20pt from the panel's top, leading, and trailing edges (equality
  constraints) and at most 20pt from the bottom edge (an inequality — see
  `bottom-inset-inequality`). Between arranged subviews,
  the default gap is `SettingsLayout.default[.groupSpacing]` = 20pt; the gap
  immediately above a heading added by `addHeading` is widened to
  `groupSpacing * 1.5` = 30pt whenever a prior arranged subview already
  exists.
- **Font**: Not applicable — `PanelView.swift` renders no text of its own.
  Group captions and heading text belong to the `GroupView` and
  `PanelHeadingView` recipes, each of which documents its own typography.
- **Background**: The theme's `.windowBackground` role
  (`palette.windowBackgroundColor`, resolved via `ThemePaletteObserver`),
  matching the source's own comment that this is "the same ground as the
  sidebar and the window."
- **Foreground/Text**: Not applicable — `PanelView` draws no text or icon of
  its own.
- **Border**: None — no border is drawn or configured anywhere in
  `PanelView.swift`.
- **Shadow**: None — no shadow is drawn or configured anywhere in
  `PanelView.swift`.
- **Min/Max size**: None declared by `PanelView` itself. Its width is
  whatever its superview gives it (no self-width constraint is set here,
  unlike `GroupView`'s own `viewDidMoveToSuperview` width match); its height
  is bounded below by `stackView`'s accumulated content plus the 20pt top
  inset, but — per `bottom-inset-inequality` — the view
  MAY be taller than that, leaving unused space below the last arranged
  subview.

## Accessibility

- **Role/trait**: Not applicable beyond AppKit's own default — `PanelView`
  sets no explicit accessibility role anywhere in `PanelView.swift`; it is a
  transparent layout container with no label, icon, or control of its own to
  expose. Each hosted `GroupView`/`PanelHeadingView` manages its own
  accessibility per its own recipe.
- **Label requirements**: Not applicable — `PanelView` itself carries no text
  or icon content; `addGroup`/`addHeading` forward the caller's views and
  strings unchanged, with no label of `PanelView`'s own to satisfy.
- **Announce state changes**: Not applicable — there is no loading or
  disabled state to announce (see States); the background repaint on a theme
  change is a silent, instantaneous recolor with no VoiceOver announcement
  anywhere in `PanelView.swift`.
- **Minimum tap target**: Not applicable — `PanelView.swift` defines no
  target/action or gesture recognizer of its own; whatever tap targets exist
  belong to the `GroupView`/`PanelHeadingView` content it hosts, covered by
  their own recipes.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `group` (`addGroup(_:)`) | `GroupView` | — (required) | The card appended as the panel's next arranged subview. |
| `title` (`addHeading(_:caption:)`) | `String` | — (required) | Heading text forwarded verbatim to the constructed `PanelHeadingView`. |
| `caption` (`addHeading(_:caption:)`) | `String?` | `nil` | Optional caption text forwarded verbatim to the constructed `PanelHeadingView`. |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `PanelView.swift` contains no animation, transition, or `NSAnimationContext`/`CATransaction` call anywhere in source; adding a group, adding a heading, and repainting the background on a theme change are each a synchronous, instantaneous assignment. |
| Increase Contrast | Not applicable to this component directly: `PanelView.swift` reads no system contrast setting and sets no literal `NSColor`; the background is a theme-resolved semantic role (`.windowBackground`) supplied by `ThemePaletteObserver`, which this file does not further adjust for contrast. |
| Differentiate Without Color | Not applicable: `PanelView` conveys no state through color; its background is decorative ground behind the groups it hosts, not a status or selection indicator. |

## Privacy

- **Data collected**: None — the component holds only the caller-supplied
  `GroupView`/`PanelHeadingView` instances it is given, plus its own
  `stackView` and `themeObserver`.
- **Storage**: Not applicable — `PanelView.swift` performs no read/write to
  disk, `UserDefaults`, or any other store.
- **Transmission**: Not applicable — no networking call appears anywhere in
  `PanelView.swift`.
- **Retention**: Not applicable — the view retains its stack, its added
  arranged subviews, and its theme observer only for its own lifetime; it
  persists nothing beyond that.

