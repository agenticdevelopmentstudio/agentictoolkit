<!-- leaf: implement-panel/heading-view · source: panel-heading-view.md -->

**Rules** (cite as `implement-panel/heading-view#<slug>`):

- `confines-to-main-actor` MUST
- `exposes-title-label` MUST
- `exposes-caption-label` MUST
- `styles-title-as-primary-heading` MUST
- `sets-title-text-from-caller` MUST
- `creates-caption-view-when-caption-given` MUST
- `omits-caption-view-when-caption-nil` MUST
- `stacks-title-and-caption-vertically-leading-aligned` MUST
- `spaces-title-from-caption` MUST
- `matches-caption-width-to-stack` MUST
- `fills-bounds-with-zero-inset` MUST
- `uses-auto-layout-exclusively` MUST
- `conforms-to-settings-view-protocol` MUST
- `rejects-frame-initializer` MUST
- `rejects-coder-initializer` MUST

# PanelHeadingView

## Overview

`ComposableSettings.PanelHeadingView`, at
`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PanelHeadingView.swift`,
is a macOS `ComposableSettings` view: an `@MainActor`, `final` `NSView`
subclass conforming to `SettingsViewProtocol` that renders a heading over a
*run* of groups, one level above a single group's own caption — distinct from
`GroupView`'s own header, which captions a single list of rows rather than a
run of groups. It pairs a `titleLabel` (a `ThemedLabel` styled as a
primary-emphasis heading) with an optional caption, which — when supplied —
is wrapped in an `ExplanationView` rather than a label of its own, so it
wraps by the one policy every settings blurb in this system shares instead of
a copy of it (see the `ExplanationView` recipe). Use it above a panel whose
groups fall into more than one kind that a reader needs to see distinguished
up front — for example, the Key Commands panel's per-window cards, split by
whether a window's commands fire only in that app or everywhere. The one call
site that constructs a `PanelHeadingView`, `PanelView.addHeading(_:
caption:)`, is not part of this recipe's source; its own spacing decision is
recorded in Design Decisions, not here.

## Behavioral Requirements

- **confines-to-main-actor**: The component MUST be usable only on the main
  actor; the class is declared `@MainActor`.
- **exposes-title-label**: The component MUST expose its heading label as a
  public, immutable stored property `titleLabel: ThemedLabel`.
- **exposes-caption-label**: The component MUST expose a public, read-only
  computed property `captionLabel: NSTextField?` that returns the caption
  view's own `label` when a caption view exists, and `nil` when it does not.
- **styles-title-as-primary-heading**: The component MUST construct
  `titleLabel` as a `ThemedLabel` with `role: .primaryText` and `textRole:
  .heading`.
- **sets-title-text-from-caller**: The component MUST initialize
  `titleLabel`'s displayed text to the caller-supplied `title: String`
  parameter, unmodified.
- **creates-caption-view-when-caption-given**: When the caller-supplied
  `caption: String?` parameter is non-`nil`, the component MUST construct
  `captionView` as an `ExplanationView(withText:)` built from that string.
- **omits-caption-view-when-caption-nil**: When the caller-supplied `caption`
  parameter is `nil`, the component MUST NOT construct a caption view; the
  internal `captionView` property MUST be `nil`.
- **stacks-title-and-caption-vertically-leading-aligned**: The component MUST
  arrange `titleLabel`, followed by `captionView` when one exists, as the
  arranged subviews (in that order) of a vertical `NSStackView` with
  `alignment == .leading`.
- **spaces-title-from-caption**: The component MUST set the stack's
  `spacing` to `SettingsLayout.default[.captionSpacing]` (6pt), regardless of
  whether a caption view is present.
- **matches-caption-width-to-stack**: When `captionView` exists, the
  component MUST constrain its width equal to the stack's `widthAnchor`. No
  equivalent width constraint is applied to `titleLabel`.
- **fills-bounds-with-zero-inset**: The component's content MUST fill the
  view's own bounds, with zero inset on every side. (See the AppKit Platform
  Notes bullet for the constraint-based mechanism.)
- **uses-auto-layout-exclusively**: The component, its internal stack, and
  `titleLabel` MUST be laid out solely through Auto Layout constraints, never
  the legacy autoresizing-mask frame system. (`captionView`, when
  constructed, manages its own Auto Layout opt-in inside `ExplanationView`'s
  own initializer — this component does not set it a second time. See the
  AppKit Platform Notes bullet for the mechanism.)
- **conforms-to-settings-view-protocol**: The component MUST conform to
  `SettingsViewProtocol`.
- **rejects-frame-initializer**: The component MUST NOT support construction
  through the frame-based initializer; calling it MUST fail unconditionally,
  regardless of the supplied frame's value. (See the AppKit Platform Notes
  bullet for the exact mechanism and message.)
- **rejects-coder-initializer**: The component MUST NOT support construction
  through coder-based initialization; calling it MUST fail. (See the AppKit
  Platform Notes bullet for the exact mechanism and message.)

## Appearance

- **Corner radius**: Not applicable — `PanelHeadingView` never sets
  `wantsLayer` or any `layer?.cornerRadius`; it is a plain `NSView` with no
  layer of its own.
- **Padding**: 0 around the component's own bounds — the stack is pinned to
  all four edges with no additional constant (`fills-bounds-with-zero-inset`).
  Internally, the gap between `titleLabel` and `captionView` (when present)
  is `SettingsLayout.default[.captionSpacing]`; treat the 6pt current value
  as illustrative, not the assertion — the token is the source of truth.
- **Font**: `titleLabel` uses the theme's `.heading` text role, sourced from
  `ThemeTypography.defaultStyle(.heading)` (illustratively 15pt `.semibold`,
  system font family, scaled by the active theme's `sizeScale` unless
  overridden — the token, not the literal, is the assertion). The caption's
  font is the theme's `.caption` text role, applied by
  `ExplanationView`/`ComposableSettings.makeValueLabel` — see the
  `ExplanationView` recipe for that view's own font details; this recipe
  does not duplicate them.
- **Background**: None/transparent — `PanelHeadingView` sets no background
  color or layer of its own, and neither `ThemedLabel` nor `ExplanationView`
  draws one either (`ThemedLabel.init` sets `drawsBackground = false`).
- **Foreground/Text**: `titleLabel`'s text color tracks the theme's
  `.primaryText` role (via `SemanticPalette.derive(_:theme:)`), undimmed
  unlike `.secondaryText`. The caption's text color is the theme's
  `.secondaryText` role, applied by `ExplanationView` — see that recipe for
  its derivation and the open question it raises about that role's contrast.
- **Border**: None — no border is drawn or configured anywhere in
  `PanelHeadingView.swift`.
- **Shadow**: None — no shadow is drawn or configured anywhere in
  `PanelHeadingView.swift`.
- **Min/Max size**: None declared by `PanelHeadingView` itself. `titleLabel`
  keeps `ThemedLabel`'s default single-line, clipped configuration
  (`PanelHeadingView.swift` never touches `titleLabel.cell?.wraps` or
  `lineBreakMode`), so it sizes to one non-wrapping line. `captionView`, when
  present, wraps across as many lines as its width (matched to the stack's
  width) requires, per `ExplanationView`'s own configuration.

## Accessibility

- **Role/trait**: `PanelHeadingView.swift` never sets an explicit
  accessibility role on `titleLabel`; AppKit exposes it, as a non-editable
  `NSTextField`, as ordinary static text, not as a heading. The component's
  stated purpose (per its own doc comment) is to caption a *run* of groups
  the way a section heading would, but the source establishes that
  relationship only visually (size and weight): it sets no accessibility
  heading role/trait (e.g. `NSAccessibilityElement`'s heading protocol, or
  `accessibilityRole`/`accessibilityRoleDescription` set to a heading value)
  on `titleLabel`, so VoiceOver users have no way to jump between panel
  headings the way heading navigation would let them.
- **Label requirements**: Satisfied for the title — `titleLabel.stringValue`
  is always the exact, caller-supplied `title` argument
  (`sets-title-text-from-caller`), which is also its accessible name under
  AppKit's default `NSTextField` behavior. The caption's own label
  requirements are covered by the `ExplanationView` recipe, not duplicated
  here — this component only forwards that view's `label` as `captionLabel`.
- **Announce state changes (e.g., loading, disabled)**: Not applicable — the
  component defines no loading or disabled state to announce (see States).
  Whether a caption exists is fixed at construction, not a runtime state
  change this component makes after the fact.
- **Minimum tap target**: Not applicable — the source defines no
  target/action, gesture recognizer, or click handling; this is a purely
  visual, non-interactive display element with no tap target to size.

## Configuration

`PanelHeadingView`
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PanelHeadingView.swift`):

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `title` | `String` | — (required) | The heading's displayed text, passed to `titleLabel` via `ThemedLabel(string:role:textRole:)` unmodified. |
| `caption` | `String?` | `nil` | Optional caption text. When non-`nil`, wrapped in an `ExplanationView` as `captionView` and arranged below the title. When `nil`, no caption view is created. |

```swift
public init(title: String, caption: String? = nil)
```

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable — the source performs no animation, transition, or `NSAnimationContext`/`CATransaction` call anywhere in `PanelHeadingView.swift`; construction is a synchronous sequence of view and constraint setup. |
| Increase Contrast | Not applicable to this component directly — `PanelHeadingView.swift` sets no custom `NSColor` and reads no system contrast setting. `titleLabel`'s color is the theme's `.primaryText` role, applied unconditionally across this whole system, not something this file computes or could get wrong independently of the palette it draws from. The caption's `.secondaryText` role carries the open question already tracked in the `ExplanationView` recipe; it is not repeated here. |
| Differentiate Without Color | Not applicable — the component conveys no state through color at all; it renders the caller-supplied title (and optional caption) in two fixed, fixed-role colors, with no color-coded meaning to differentiate. |

## Privacy

- **Data collected**: None — the view holds only the `title`/`caption`
  strings passed to it by the caller; it originates no data of its own.
- **Storage**: Not applicable — the source performs no persistence of any
  kind.
- **Transmission**: Not applicable — no networking call appears anywhere in
  `PanelHeadingView.swift`.
- **Retention**: Not applicable — the view retains only `titleLabel` and, if
  constructed, `captionView`, for its own lifetime.

