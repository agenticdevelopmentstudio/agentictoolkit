---
id: 9e21151e-dc58-49a2-be1e-4984529f4396
title: PanelHeadingView
domain: agentictoolkit://recipes/panel-heading-view
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: An AppKit macOS NSView pairing a primary-styled heading label with an optional
  wrapping ExplanationView caption, used above a run of settings groups in a ComposableSettings
  panel.
platforms:
- swift
- macos
tags:
- settings
- heading
- macos
- appkit
depends-on: []
related:
- agentictoolkit://recipes/explanation-view
- agentictoolkit://recipes/header-view
references:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
approved-by: ''
approved-date: ''
---

# PanelHeadingView

## Overview

`ComposableSettings.PanelHeadingView`, at
`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PanelHeadingView.swift`,
is a macOS `ComposableSettings` view: an `@MainActor`, `final` `NSView`
subclass conforming to `SettingsViewProtocol` that renders a heading over a
*run* of groups, one level above a single group's own caption. The source's
own doc comment draws the distinction explicitly: "A panel whose groups all
belong to one list needs nothing above them — which is why this is not what
`GroupView`'s header is. It exists for the panel whose cards divide into two
kinds, where the kind is the first thing a reader has to know: the Key
Commands panel lists a card per window, and whether a window's commands fire
only in this app or everywhere is what separates them." It pairs a
`titleLabel` (a `ThemedLabel` styled as a primary-emphasis heading) with an
optional caption, which — when supplied — is wrapped in an `ExplanationView`
rather than a label of its own; the source's own comment on `captionView`
states this is "so it wraps inside the panel by the one policy every settings
blurb shares instead of a copy of it," pointing at the sibling
`ExplanationView` recipe for that wrapping behavior. `PanelView.addHeading(_:
caption:)` (`PanelView.swift`, not part of this recipe's source) is the one
call site in this codebase that constructs a `PanelHeadingView`; it also
widens the gap above the heading to `1.5×` the panel's group spacing before
adding it, but that spacing decision lives in `PanelView.swift`, not in
`PanelHeadingView.swift`, so it is not a requirement of this component (see
Design Decisions).

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
- **pins-stack-to-own-edges**: The component MUST activate four
  `NSLayoutConstraint`s pinning the stack's top, leading, trailing, and
  bottom anchors to the matching anchors of the component itself, each with a
  zero constant.
- **disables-autoresizing-mask-on-self-stack-and-title**: The component MUST
  set `translatesAutoresizingMaskIntoConstraints = false` on itself, on the
  internal stack, and on `titleLabel`. (`captionView`, when constructed,
  disables its own autoresizing-mask translation inside `ExplanationView`'s
  own initializer — this component does not set it a second time.)
- **conforms-to-settings-view-protocol**: The component MUST conform to
  `SettingsViewProtocol`.
- **rejects-frame-initializer**: The designated `init(frame frameRect:
  NSRect)` initializer MUST fatal-error unconditionally, regardless of the
  supplied `frameRect`'s value, with the message `init(frame frameRect:
  NSRect)` (verbatim).
- **rejects-coder-initializer**: `required init?(coder: NSCoder)` MUST
  fatal-error with the message `init(coder:) has not been implemented`.

## Appearance

- **Corner radius**: Not applicable — `PanelHeadingView` never sets
  `wantsLayer` or any `layer?.cornerRadius`; it is a plain `NSView` with no
  layer of its own.
- **Padding**: 0 around the component's own bounds — the stack is pinned to
  all four edges with no additional constant (`pins-stack-to-own-edges`).
  Internally, the gap between `titleLabel` and `captionView` (when present)
  is `SettingsLayout.default[.captionSpacing]` = 6pt.
- **Font**: `titleLabel` uses the theme's `.heading` text role
  (`ThemeTypography.defaultStyle(.heading)` = 15pt, `.semibold` weight,
  system font family, scaled by the active theme's `sizeScale` unless
  overridden). The caption's font is the theme's `.caption` text role,
  applied by `ExplanationView`/`ComposableSettings.makeValueLabel` — see the
  `ExplanationView` recipe for that view's own font details; this recipe
  does not duplicate them.
- **Background**: None/transparent — `PanelHeadingView` sets no background
  color or layer of its own, and neither `ThemedLabel` nor `ExplanationView`
  draws one either (`ThemedLabel.init` sets `drawsBackground = false`).
- **Foreground/Text**: `titleLabel`'s text color tracks the theme's
  `.primaryText` role, which `SemanticPalette.derive(_:theme:)` returns as
  the theme's foreground color directly (undimmed, unlike `.secondaryText`'s
  algorithmic dimming). The caption's text color is the theme's
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

## States

| State | Appearance change |
|-------|------------------|
| Default | Renders `titleLabel`'s text at the `.primaryText`/`.heading` style; whether a caption follows depends on the `caption` argument given at construction. |
| Caption present | `captionView` is constructed and arranged below `titleLabel`, 6pt apart, its width matched to the stack; `captionLabel` returns its `label`. |
| Caption absent | `captionView` is `nil` and never constructed; only `titleLabel` is an arranged subview; `captionLabel` returns `nil`. |
| Pressed | Not applicable: the source defines no target/action, gesture recognizer, or tracking area — `PanelHeadingView` has no pressed interaction to represent. |
| Disabled | Not applicable: the source exposes no enabled/disabled API; it defines no `isEnabled` property or dimmed-appearance logic. |
| Focused | Not applicable: the view never becomes key/first responder; the source overrides no responder-chain behavior, and `NSView`'s own default (`acceptsFirstResponder == false`) applies unmodified. |
| Loading | Not applicable: the source performs no asynchronous operation and defines no loading flag, spinner, or placeholder state. |

## Accessibility

- **Role/trait**: NEEDS REVIEW: `PanelHeadingView.swift` never sets an
  explicit accessibility role on `titleLabel`. AppKit exposes it, as a
  non-editable `NSTextField`, as ordinary static text — not as a heading. The
  component's entire stated purpose (per its own doc comment) is to caption a
  *run* of groups the way a section heading would, yet nothing in source
  gives VoiceOver users a way to jump between panel headings the way heading
  navigation would let them. What is missing: an explicit accessibility
  heading role/trait (e.g. `NSAccessibilityElement`'s heading protocol, or
  `accessibilityRole`/`accessibilityRoleDescription` set to a heading value)
  on `titleLabel`. What would settle it: confirmation from the
  accessibility/HIG owner on whether `PanelHeadingView` should mark
  `titleLabel` as an accessibility heading, since the source as written only
  establishes the relationship visually (size and weight), not
  programmatically.
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

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| panel-heading-view-001 | confines-to-main-actor | Attempt to construct or mutate a `PanelHeadingView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| panel-heading-view-002 | exposes-title-label | Construct `PanelHeadingView(title: "Section")` | `view.titleLabel` is accessible from outside the class and is a `ThemedLabel` instance |
| panel-heading-view-003 | exposes-caption-label | Construct `PanelHeadingView(title: "Section", caption: "Some blurb")` | `view.captionLabel` is non-`nil` and equals the constructed `captionView`'s `label` |
| panel-heading-view-004 | exposes-caption-label | Construct `PanelHeadingView(title: "Section")` (no `caption` argument) | `view.captionLabel` is `nil` |
| panel-heading-view-005 | styles-title-as-primary-heading | Construct `PanelHeadingView(title: "Section")` | `view.titleLabel.role == .primaryText` and `view.titleLabel.textRole == .heading` |
| panel-heading-view-006 | sets-title-text-from-caller | Construct `PanelHeadingView(title: "General")` | `view.titleLabel.stringValue == "General"` |
| panel-heading-view-007 | creates-caption-view-when-caption-given | Construct `PanelHeadingView(title: "Section", caption: "Some blurb")` | The stack's arranged subviews include an `ExplanationView` whose `label.stringValue == "Some blurb"` |
| panel-heading-view-008 | omits-caption-view-when-caption-nil | Construct `PanelHeadingView(title: "Section")` with `caption` defaulted to `nil` | The stack's arranged subviews contain no `ExplanationView`; `view.captionLabel == nil` |
| panel-heading-view-009 | stacks-title-and-caption-vertically-leading-aligned | Construct `PanelHeadingView(title: "Section", caption: "Some blurb")` | The internal stack's `orientation == .vertical`, `alignment == .leading`, and `arrangedSubviews == [titleLabel, captionView]` in that order |
| panel-heading-view-010 | spaces-title-from-caption | Construct the component (with or without a caption) | The internal stack's `spacing == 6.0` |
| panel-heading-view-011 | matches-caption-width-to-stack | Construct `PanelHeadingView(title: "Section", caption: "Some blurb")` | An active constraint equates `captionView`'s width to the stack's `widthAnchor`; no equivalent constraint exists for `titleLabel` |
| panel-heading-view-012 | pins-stack-to-own-edges | Construct the component | Active constraints pin the stack's top/leading/trailing/bottom anchors to the view's corresponding anchors, each with constant `0` |
| panel-heading-view-013 | disables-autoresizing-mask-on-self-stack-and-title | Construct the component | `translatesAutoresizingMaskIntoConstraints == false` on the view, the internal stack, and `titleLabel` |
| panel-heading-view-014 | conforms-to-settings-view-protocol | Any initialized `PanelHeadingView` | `view is SettingsViewProtocol` is `true` |
| panel-heading-view-015 | rejects-frame-initializer | Construct via `PanelHeadingView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))` | Execution traps via `fatalError` with message `init(frame frameRect: NSRect)` |
| panel-heading-view-016 | rejects-coder-initializer | Construct via `PanelHeadingView(coder:)` with any `NSCoder` | Execution traps via `fatalError` with message `init(coder:) has not been implemented` |

## Edge Cases

- **Null/empty input**: `title` is a required, non-optional `String`
  parameter, so Swift's type system rules out `nil`. An empty string (`""`)
  renders an empty `titleLabel` with no guard against it in source (MUST,
  per `sets-title-text-from-caller`). `caption` is `String?` and defaults to
  `nil`; an explicit empty string (`caption: ""`) is non-`nil`, so it MUST
  still construct a caption view whose label renders empty
  (`creates-caption-view-when-caption-given` does not special-case an empty
  but non-`nil` string).
- **Boundary values**: Not applicable in the numeric sense — the component's
  only inputs are the two caller-supplied strings; it has no
  caller-configurable numeric range. A very long `title` is clipped, not
  wrapped, because `PanelHeadingView.swift` never reconfigures `titleLabel`'s
  wrap settings; a very long `caption` wraps across more lines instead,
  because its width is matched to the stack (`matches-caption-width-to-stack`)
  while `ExplanationView` itself is configured to wrap.
- **Concurrent access**: Not applicable — the class is `@MainActor`-isolated;
  the Swift compiler rejects construction or mutation of `self`, `titleLabel`,
  or `captionView` from off the main actor.
- **Error states (dependency/network failure)**: Not applicable — the source
  performs no I/O, network call, or dependency lookup of any kind.
- **Offline/disconnected state**: Not applicable — `PanelHeadingView`
  performs no networking of its own.
- **Caption text reassigned after construction**: `PanelHeadingView` exposes
  `captionLabel` as `NSTextField?`, so a caller with a non-`nil` caption can
  reassign `captionLabel?.stringValue` directly; this is the same pattern the
  `ExplanationView` recipe documents for its own `label` property, reached
  here through the forwarding `captionLabel` computed property rather than
  any `update`/`setText` method `PanelHeadingView` itself defines (SHOULD,
  by extension of `ExplanationView`'s own `updates-text-via-label-property`
  guidance — see Design Decisions).
- **Constructed with `caption: nil` and later needing one**: `captionView`
  is a `private let`-equivalent, constructed once at `init` time and never
  reassigned; the source provides no way to add a caption to a
  `PanelHeadingView` that was built without one — a caller that needs a
  caption MUST supply it at construction (MUST-level, source-traceable
  consequence of `omits-caption-view-when-caption-nil`: no method exists to
  set `captionView` after `init` returns).

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

## Deep Linking

Not applicable: `PanelHeadingView` is a display-only heading inside a
composable settings panel, not a navigable screen; no URL scheme, route, or
deep-link handler appears anywhere in `PanelHeadingView.swift`.

## Localization

Not applicable: both `title` and `caption` are entirely caller-supplied
`String`/`String?` parameters, not literals owned by this type.
`PanelHeadingView.swift` defines no string literal of its own that would
need translation; producing localized text is the caller's responsibility
before either parameter reaches this initializer.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable — the source performs no animation, transition, or `NSAnimationContext`/`CATransaction` call anywhere in `PanelHeadingView.swift`; construction is a synchronous sequence of view and constraint setup. |
| Increase Contrast | Not applicable to this component directly — `PanelHeadingView.swift` sets no custom `NSColor` and reads no system contrast setting. `titleLabel`'s color is the theme's `.primaryText` role, applied unconditionally across this whole system, not something this file computes or could get wrong independently of the palette it draws from. The caption's `.secondaryText` role carries the open question already tracked in the `ExplanationView` recipe; it is not repeated here. |
| Differentiate Without Color | Not applicable — the component conveys no state through color at all; it renders the caller-supplied title (and optional caption) in two fixed, fixed-role colors, with no color-coded meaning to differentiate. |

## Feature Flags

Not applicable: the source contains no feature-flag lookup or conditional
gate; the view renders unconditionally whenever constructed.

## Analytics

Not applicable: the source contains no analytics, tracking, or telemetry
call.

## Privacy

- **Data collected**: None — the view holds only the `title`/`caption`
  strings passed to it by the caller; it originates no data of its own.
- **Storage**: Not applicable — the source performs no persistence of any
  kind.
- **Transmission**: Not applicable — no networking call appears anywhere in
  `PanelHeadingView.swift`.
- **Retention**: Not applicable — the view retains only `titleLabel` and, if
  constructed, `captionView`, for its own lifetime.

## Logging

Not applicable: the source contains no logging call (no `print`, `os_log`,
or logger reference anywhere in `PanelHeadingView.swift`).

## Platform Notes

- **SwiftUI**: Compose a `VStack(alignment: .leading, spacing: 6)` with a
  `Text(title).font(.headline)` (or the app's `.heading` theme token) for the
  title, and — only when `caption` is non-`nil` — a `Text(caption)
  .font(.caption).foregroundStyle(.secondary)
  .fixedSize(horizontal: false, vertical: true)` beneath it, mirroring
  `stacks-title-and-caption-vertically-leading-aligned` and
  `creates-caption-view-when-caption-given`/
  `omits-caption-view-when-caption-nil`. Give the caption `Text` no fixed
  frame beyond the parent's own width so it wraps to it, the SwiftUI analog
  of `matches-caption-width-to-stack`; leave the title unconstrained in width
  to match the source's clipped, single-line title.
- **Compose**: Use a `Column(verticalArrangement = Arrangement
  .spacedBy(6.dp), horizontalAlignment = Alignment.Start)` with a
  `Text(title, style = MaterialTheme.typography.titleMedium)` for the
  heading, and conditionally (`if (caption != null)`) a
  `Text(caption, style = MaterialTheme.typography.bodySmall, color =
  MaterialTheme.colorScheme.onSurfaceVariant)` that wraps within the
  column's own width — Compose `Text` wraps by default, mirroring the
  caption's wrapping behavior without extra configuration.
- **React/Web**: A `<hgroup>` or `<div>` containing a heading element (e.g.
  `<h3>`) styled from the primary-text/heading tokens, followed — only when
  `caption` is provided — by a `<p>` styled from the
  secondary-text/caption tokens with `white-space: normal; overflow-wrap:
  break-word` and `width: 100%` so it wraps to the container, mirroring
  `matches-caption-width-to-stack`; use `gap: 6px` (flex or grid column) for
  the title-to-caption spacing, matching `spaces-title-from-caption`.
- **AppKit / UIKit** (source platform): Source at
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PanelHeadingView.swift`
  (this recipe's source): a macOS-only (`import AppKit`) `NSView` subclass,
  `@MainActor`, `final`, inside the `ComposableSettings` namespace, composing
  one `ThemedLabel` and, conditionally, one `ExplanationView` inside an
  `NSStackView`. There is no UIKit code path in source. A UIKit port would
  replace `NSStackView` with `UIStackView`, `ThemedLabel`(`NSTextField`) with
  a `UILabel` styled for the heading role, and the conditionally-constructed
  `ExplanationView`/`UILabel` pairing for the caption; it would have no
  `NSCoder`-vs-frame initializer split to fatal-error on the way
  `rejects-frame-initializer` and `rejects-coder-initializer` do.
- **WinUI 3** (the reason this recipe exists): Build this as a vertical
  `StackPanel` with `Spacing="6"` (the analog of
  `SettingsLayout.default[.captionSpacing]` /
  `spaces-title-from-caption`) containing a `TextBlock` styled
  `Style="{StaticResource BodyStrongTextBlockStyle}"` (or a custom style
  matching the theme's `.heading` size/weight) bound to `title`, mirroring
  `styles-title-as-primary-heading`/`sets-title-text-from-caller`. Add a
  second `TextBlock` — constructed and added to the `StackPanel.Children`
  only when `caption` is non-null, not merely hidden via `Visibility`, to
  mirror `creates-caption-view-when-caption-given`/
  `omits-caption-view-when-caption-nil` and to keep `PanelHeadingView`'s own
  `captionLabel == nil` contract honest for a null caption — styled
  `Style="{StaticResource CaptionTextBlockStyle}"` with
  `TextWrapping="WrapWholeWords"` and `HorizontalAlignment="Stretch"` so it
  wraps to the `StackPanel`'s own width, mirroring
  `matches-caption-width-to-stack` (a `StackPanel`'s children stretch to its
  width by default when no narrower `Width` is set, unlike `titleLabel`,
  which should keep `TextWrapping="NoWrap"` and `TextTrimming="Clip"` to
  match the source's untouched, single-line `ThemedLabel` default). There is
  no WinUI equivalent of `NSLayoutConstraint`-based edge pinning needed
  beyond placing the `StackPanel` alone in its parent cell with no `Margin`,
  reproducing `pins-stack-to-own-edges` directly.

## Design Decisions

- **Decision**: The caption, when supplied, is wrapped in an
  `ExplanationView` rather than being built as a second `ThemedLabel` local
  to `PanelHeadingView`.
  **Rationale**: per the source's own comment on `captionView`, this is "so
  it wraps inside the panel by the one policy every settings blurb shares
  instead of a copy of it" — the wrapping, compression, and hugging behavior
  a multi-line settings caption needs is owned once, by `ExplanationView`,
  and reused here rather than re-implemented.
  **Approved: pending**
- **Decision**: `titleLabel`'s width is never constrained to the stack's
  width, while `captionView`'s width is (`matches-caption-width-to-stack`).
  **Rationale**: not explained in source comments beyond the code itself.
  `titleLabel` keeps `ThemedLabel`'s default single-line, clipped
  configuration and needs no width constraint to wrap correctly; `captionView`
  wraps by design (per `ExplanationView`'s own configuration) and needs a
  known width to wrap *against* — without the constraint, a wrapping label
  reports its one-line intrinsic width instead of the width the panel
  actually gives it, the same reasoning the `ExplanationView` recipe
  documents for that view's own horizontal-compression decision.
  **Approved: pending**
- **Decision**: The gap above a `PanelHeadingView` inside a panel is widened
  to `1.5×` the panel's group spacing by `PanelView.addHeading(_:caption:)`,
  not by `PanelHeadingView` itself.
  **Rationale**: `PanelView.swift`'s own comment on `addHeading` states "the
  gap above a heading is wider than the gap between two cards, because that
  gap is what says the heading belongs to what comes *after* it — at the
  stack's own spacing it reads as a caption trailing the card above." This
  spacing decision is recorded here for context because it is the one call
  site that constructs this component, but `PanelView.swift` is not part of
  this recipe's source, so it is not a requirement of `PanelHeadingView`
  itself.
  **Approved: pending**
- **Decision**: `init(frame frameRect: NSRect)`'s fatal-error message,
  `"init(frame frameRect: NSRect)"`, is correctly parenthesized here, unlike
  the malformed (missing-parenthesis) message the sibling `ExplanationView`
  and `HeaderView` recipes document for their own frame initializers.
  **Rationale**: documented as a source-traceable difference between
  siblings, not smoothed over in either direction — this file's message
  string is well-formed as written; the other two are not.
  **Approved: pending**
- **Decision**: This recipe has fewer behavioral requirements than the
  sibling `GroupView` recipe (33) but more than the sibling `HeaderView`
  recipe (11).
  **Rationale**: `PanelHeadingView` is `HeaderView`'s title/caption
  composition made optional-caption-aware, with no card, no rows, and no
  separator logic — genuinely simpler than `GroupView`'s row-management
  responsibilities, and modestly more complex than `HeaderView`'s single
  fixed label. The requirement count reflects that difference in scope, not
  a gap in authoring effort.
  **Approved: pending**

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [main-actor-confined](agenticdevelopercookbook://compliance/architecture#main-actor-confined) | passed | architecture |
| [no-raw-hex](agenticdevelopercookbook://compliance/ui-tokens#no-raw-hex) | passed | ui-tokens |
| [theme-driven-typography](agenticdevelopercookbook://compliance/ui-tokens#theme-driven-typography) | passed | ui-tokens |
| [differentiate-without-color](agenticdevelopercookbook://compliance/accessibility#differentiate-without-color) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | needs-review | accessibility |
| [localizable-strings](agenticdevelopercookbook://compliance/i18n#localizable-strings) | passed | i18n |

`main-actor-confined` passes because the class is declared `@MainActor` (see
`confines-to-main-actor`). `no-raw-hex` passes because every color this
component displays comes from `titleLabel`'s `.primaryText` role or
`captionView`'s `.secondaryText` role, never a literal `NSColor` or hex
value. `theme-driven-typography` passes because both the title's `.heading`
font and the caption's `.caption` font come from `ThemeTypography`, not a
hardcoded point size or weight. `differentiate-without-color` passes because
the component conveys no state through color. `screen-reader-support` needs
review because of the open heading-role question recorded under
Accessibility above. `localizable-strings` passes because `title` and
`caption` are entirely caller-supplied strings with no literal owned by this
file.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation, extracted from the Apple `PanelHeadingView` (AppKit, macOS) source. |
