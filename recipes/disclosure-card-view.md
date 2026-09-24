---
id: d5aba939-471d-48cd-9a9c-888ac92adf38
title: DisclosureCardView
domain: agentictoolkit://recipes/disclosure-card-view
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: An AppKit card with an elevated titlebar, a native disclosure triangle, optional
  accessories, a right-aligned collapsed summary line, and a top-right status badge.
platforms:
- swift
- macos
tags:
- card
- disclosure
- collapsible
- macos
- appkit
depends-on: []
related: []
references:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
approved-by: ''
approved-date: ''
---

# DisclosureCardView

## Overview

`DisclosureCardView`, at
`packages/apple/AgenticToolkit/macOS/UI/Cards/DisclosureCardView.swift`, is an
`@MainActor`, `NSView`-subclassed, `Themeable` card that folds: a rounded,
bordered surface with an elevated titlebar strip naming it (a title, an
optional leading accessory, an optional trailing accessory, and a native
disclosure triangle), and whatever host content is added beneath that. Folding
the card hides its content and, if the card carries `summary` readings, shows
a single right-aligned line of them under the title instead; a folded card
with no summary is exactly its titlebar and nothing else. The card can also
show one status badge stamped on its top-right corner. Its own width never
changes between open and folded states, because both states' content is
measured and the wider is reserved regardless of which is currently drawn.
Tapping the disclosure triangle does not fold the card itself — it reports the
requested new state through `onToggle` and leaves layout untouched; the host
is expected to rebuild the card with a new `isCollapsed` value (typically via
the companion `CardFoldMemory` helper in the same directory, which persists
the folded set and rebuilds on toggle).

## Behavioral Requirements

- **renders-card-as-rounded-bordered-surface**: Component MUST render a
  `surface` subview pinned to all four edges of the card with a 10pt corner
  radius (`cornerRadius`), a 1pt border (`borderWidth`), a background of the
  palette's `surfaceColor`, and a border color of the palette's
  `outlineColor`.
- **clips-titlebar-to-card-corners**: Component MUST set
  `surface.layer?.masksToBounds = true`, so the titlebar strip's own square
  top corners are clipped to the card's rounded ones.
- **renders-titlebar-as-elevated-strip**: Component MUST fill the titlebar
  strip with the palette's `elevatedSurfaceColor`, distinct from the card
  body's `surfaceColor`.
- **draws-titlebar-rule**: Component MUST draw a hairline (`borderWidth`,
  1pt) along the titlebar's bottom edge, filled with the palette's
  `dividerColor` and spanning the titlebar's full leading-to-trailing width.
- **sizes-titlebar-to-header-plus-inset**: Component MUST size the titlebar
  strip's height to the header row's (title line plus trailing line) height
  plus `padTitleY` below it, never to the body's height.
- **draws-badge-above-surface-border**: Component MUST add the status badge
  (`statusIcon`) as a sibling subview added after `surface`, so it paints
  above the surface's own border layer, which a `CALayer` otherwise draws
  above all of that layer's sublayers.
- **allows-badge-to-render-outside-frame**: Component MUST set
  `clipsToBounds = false` on itself, so the status badge can be drawn
  partially outside the card's own frame.
- **displays-title-text**: Component MUST display the exact `title` string
  passed to `init` in the titlebar via `titleField`.
- **truncates-title-in-middle**: Component MUST truncate `titleField`'s text
  in the middle (`lineBreakMode = .byTruncatingMiddle`) when it does not fit
  the available width.
- **yields-title-width-first**: Component MUST give `titleField` and
  `titleLine` `.defaultLow` horizontal compression-resistance and content-
  hugging priority, the lowest of any element on the header row, so the
  title is the first thing to shrink when the row is too narrow.
- **colors-title-by-accent-flag**: Component MUST color `titleField` with
  the palette's `accentColor` when `titleIsAccent == true`, and with
  `primaryTextColor` otherwise.
- **sets-title-font-semibold-body**: Component MUST set `titleField`'s font
  to the palette's `.body` typography style with its `weight` overridden to
  `.semibold`, resolved to an `NSFont` at `scaledSize`.
- **places-title-accessory-leading**: When `titleAccessory` is non-nil,
  Component MUST place it immediately before `titleField` inside
  `titleLine`, separated by `iconGap` (6pt, unscaled), and MUST give the
  accessory required horizontal compression resistance so only the title
  text — never the accessory — yields width.
- **places-titlebar-accessory-before-disclosure**: When `titlebarAccessory`
  is non-nil, Component MUST place it immediately before the disclosure
  control inside `trailingLine`, separated by `iconGap`.
- **never-shrinks-trailing-line**: Component MUST give `trailingLine` (the
  titlebar accessory, if any, plus the disclosure control) required
  horizontal compression-resistance and content-hugging priority, so it
  never yields width to the title line.
- **maintains-minimum-header-gap**: Component MUST keep at least
  `mastheadGap` (8pt) between `titleLine`'s trailing edge and
  `trailingLine`'s leading edge, and MUST vertically center-align the two
  lines on the header row (`PinnedEndsLine.make(..., alignment: .centerY)`).
- **renders-native-disclosure-control**: Component MUST render the fold
  control as an `NSButton` with `bezelStyle = .disclosure` and
  `buttonType = .onOff`, rather than a custom-drawn chevron.
- **sets-disclosure-initial-state**: Component MUST set the disclosure
  control's `state` to `.off` when constructed with `isCollapsed == true`,
  and to `.on` when constructed with `isCollapsed == false`.
- **labels-disclosure-control**: Component MUST set the disclosure
  control's `toolTip` and accessibility label to `"Show details"` when
  constructed with `isCollapsed == true`, and to `"Hide details"` when
  constructed with `isCollapsed == false`.
- **forwards-toggle-state**: Component MUST invoke `onToggle`, passing
  `true` when the disclosure control's `state` becomes `.off` and `false`
  when it becomes `.on`, whenever the user clicks the disclosure control.
- **does-not-self-mutate-on-toggle**: Component MUST NOT change
  `content.isHidden`, `body.isHidden`, subtitle visibility, or the
  disclosure control's own `toolTip`/accessibility label as a direct result
  of a disclosure click — `disclosureTapped` only calls `onToggle`. Folding
  is applied only by the host reconstructing the view with a new
  `isCollapsed` (see Design Decisions).
- **hides-content-when-collapsed**: Component MUST set
  `content.isHidden = true` for the lifetime of an instance constructed
  with `isCollapsed == true`, and `false` for one constructed with
  `isCollapsed == false`.
- **builds-content-regardless-of-fold-state**: Component MUST add every
  view passed to `addContent(_:)` to `content` regardless of the card's
  current fold state, so a folded card's content remains measurable.
- **forces-subtitle-hidden-when-collapsed**: Component MUST hide
  `subtitleField` when constructed with `isCollapsed == true`, even when a
  non-nil `subtitle` was supplied.
- **hides-subtitle-when-absent**: Component MUST hide `subtitleField` when
  `subtitle == nil`.
- **detaches-empty-body**: Component MUST hide the entire `body` stack
  (summary row, subtitle, and content) when constructed with
  `isCollapsed == true` and an empty `summary`, so the card renders as
  exactly its titlebar with no residual empty space beneath it.
- **matches-bottom-inset-to-empty-body**: Component MUST use `padTitleY`,
  not the larger `padY`, as its own bottom inset when `body` is hidden, so a
  titlebar-only card's bottom edge sits `padTitleY` under the header,
  matching the header's own top inset.
- **shows-summary-only-when-collapsed-and-present**: Component MUST show
  `summaryField` only when constructed with `isCollapsed == true` AND a
  non-empty `summary`; it MUST be hidden in every other combination of
  those two inputs.
- **right-aligns-and-clips-summary-text**: Component MUST right-align
  `summaryField`'s text, give it required horizontal compression
  resistance, and set `lineBreakMode = .byClipping` (clip rather than
  truncate-with-ellipsis if the reserved width is ever exceeded).
- **formats-summary-parts**: Component MUST render each `SummaryPart` as
  `"<name>: <value>"`, with `name` in the palette's `.caption` style at
  `scaledSize × 0.85` colored `tertiaryTextColor`, and `value` in the
  palette's `.code` style at the same size colored by
  `part.color(palette)`, falling back to `secondaryTextColor` when that
  closure returns `nil`.
- **separates-summary-parts**: Component MUST insert a `"  |  "` separator,
  styled like a summary name (caption font, `tertiaryTextColor`), between
  each pair of adjacent `SummaryPart`s, and MUST NOT insert one before the
  first part or after the last.
- **hides-status-badge-when-absent**: Component MUST hide `statusIcon` when
  `status == nil`.
- **renders-status-as-sf-symbol**: Component MUST render a non-nil `status`
  as `NSImage(systemSymbolName: status.symbolName, accessibilityDescription:
  status.accessibilityLabel)`, with a symbol configuration of `.semibold`
  weight at a point size equal to `cornerBadgeDiameter(scaledSize:)`.
- **exposes-status-as-own-accessibility-element**: Component MUST expose a
  non-nil `statusIcon` as its own accessibility element with role `.image`
  and accessibility label `status.accessibilityLabel`, and MUST set that
  same string as its `toolTip`.
- **colors-status-badge**: Component MUST tint `statusIcon` with
  `palette.color(named: status?.colorName)`, falling back to
  `secondaryTextColor` whenever that lookup returns `nil` (including when
  `status` itself is `nil` or its `colorName` is `nil`).
- **positions-badge-on-visible-corner**: Component MUST center the status
  badge, on both axes, `cornerPeakInset` (`cornerRadius − cornerRadius/√2`,
  ≈2.93pt at the fixed 10pt radius) inside the card's top-right corner —
  the point where the rounded corner's arc actually turns — not on the
  frame's literal square corner.
- **sizes-badge-diameter**: Component MUST size the status badge to
  `min(ceil(scaledSize × 1.3), padXFor(scaledSize) × 1.5)` on each axis.
- **dims-whole-card-uniformly**: Component MUST set the entire view's
  `alphaValue` to 0.55 when constructed with `isDimmed == true`, and to
  `1.0` otherwise, rather than substituting a separate set of dimmed
  colors.
- **scales-insets-with-text-size**: Component MUST scale
  `horizontalInset` (14), `mastheadInset` (7), `verticalInset` (12), and
  `titlebarInset` (6) linearly by `scaledSize ÷ NSFont.systemFontSize`,
  rounding each result up (`ceil`), rather than using fixed point values.
- **floors-width-to-wider-of-open-or-folded-content**: Component MUST
  constrain its own width to be greater than or equal to the wider of (a)
  `content`'s fitting width and (b) the masthead's folded-state width (the
  title-plus-trailing-line row, or the summary line, whichever is wider) —
  plus the masthead's leading and trailing gutters — regardless of whether
  the card is currently open or folded.
- **keeps-width-floor-just-under-required**: Component MUST set the width-
  floor constraint's priority to `999` (just under `.required`), so a
  container too narrow for the content scrolls rather than making the
  layout unsatisfiable.
- **remeasures-width-floor-on-layout**: Component MUST recompute its width
  floor on every `layout()` pass, but MUST only apply the newly computed
  constant when it differs from the current one by more than 0.5pt.
- **applies-theme-immediately-and-on-change**: Component MUST apply the
  current theme once at construction and again on every subsequent theme
  change, via a `ThemePaletteObserver` held for the view's lifetime.
- **rejects-storyboard-instantiation**: Component MUST fail with a fatal
  error if constructed via `init?(coder:)` (declared
  `@available(*, unavailable)`).
- **confines-mutation-to-main-actor**: Component MUST only be constructed
  or mutated from the main actor; the class and its public API are
  declared `@MainActor`.
- **exposes-content-spacing**: Component MUST expose a `contentSpacing`
  property that reads and writes `content.spacing`, and MUST re-measure the
  width floor whenever it is set.
- **prefers-dynamic-summary-colors**: Callers SHOULD build `SummaryPart`
  values whose `color` closure resolves against the live `SemanticPalette`
  each time it is called (as the `init(name:value:colorName:)` convenience
  does) rather than capturing a static `NSColor`, per the type's own doc
  comment ("a closure rather than a colour name... so a card already on
  screen recolours with everything else when the theme changes"). This
  constrains what callers pass in, not an observable behavior Component
  itself can verify — no test vector applies (see Design Decisions).

## Appearance

- **Corner radius**: 10pt, fixed (`cornerRadius`); unaffected by
  `scaledSize`.
- **Padding**: `padX` = `ceil(14 × scaledSize / NSFont.systemFontSize)` from
  the card edge to body/content rows and to the summary/subtitle's trailing
  edge; `padMastheadX` = `ceil(7 × scaledSize / NSFont.systemFontSize)` from
  the card edge to the masthead line's leading edge; `padY` =
  `ceil(12 × scaledSize / NSFont.systemFontSize)` as the card's own bottom
  inset when `body` is present; `padTitleY` =
  `ceil(6 × scaledSize / NSFont.systemFontSize)` as the titlebar's own
  top/bottom inset, and as the card's bottom inset when `body` is hidden;
  `iconGap` = 6pt fixed between an accessory and the text/control beside
  it; `mastheadGap` = 8pt minimum between the title line and the trailing
  line.
- **Font**: title — palette `.body` style, weight forced to `.semibold`, at
  `scaledSize`; subtitle and summary names — palette `.caption` style at
  `scaledSize × 0.85`; summary values — palette `.code` style at
  `scaledSize × 0.85`.
- **Background**: card body — palette `surfaceColor`; titlebar strip —
  palette `elevatedSurfaceColor`.
- **Foreground/Text**: title — `accentColor` when `titleIsAccent`,
  otherwise `primaryTextColor`; subtitle, summary names, and the summary
  separator — `tertiaryTextColor`; summary values — each `SummaryPart`'s
  own resolved color, falling back to `secondaryTextColor`; disclosure
  control tint — `secondaryTextColor`; status badge tint — the palette
  color named by `status.colorName`, falling back to `secondaryTextColor`.
- **Border**: card surface — 1pt, palette `outlineColor`; titlebar rule —
  1pt, palette `dividerColor` (a filled strip along the titlebar's bottom
  edge, not a stroked `CALayer` border).
- **Shadow**: none — the source sets no `shadowColor`, `shadowRadius`, or
  `shadowOpacity` on any layer.
- **Min/Max size**: none declared as fixed constants. The card's only size
  constraint is the dynamic width floor (`contentWidthFloor`, priority
  999) described above; no explicit minimum or maximum height, and no
  upper bound on width.

## States

| State | Appearance change |
|-------|------------------|
| Default (expanded, `isCollapsed: false`) | Titlebar strip and full `content` body are drawn; `subtitleField` shown if `subtitle` is non-nil; `summaryField` hidden; disclosure `state = .on`, tooltip/label "Hide details" |
| Collapsed (`isCollapsed: true`) | `content.isHidden = true`; `subtitleField` forced hidden regardless of `subtitle`; `summaryField` shown, right-aligned, if `summary` is non-empty; if `summary` is also empty, `body` is entirely hidden and the card renders as exactly its titlebar; disclosure `state = .off`, tooltip/label "Show details" |
| Dimmed (`isDimmed: true`) | Whole view `alphaValue = 0.55`; no separate dimmed color set is used — every color the card draws is unchanged, only faded uniformly |
| Pressed | Not applicable beyond the embedded disclosure `NSButton`'s own native pressed bezel: `DisclosureCardView` itself has no target/action or tracking area of its own and draws no custom pressed appearance. |
| Focused | Not applicable: `DisclosureCardView` never overrides `acceptsFirstResponder` or focus-ring drawing; the only focusable subview is the disclosure `NSButton`, which gets AppKit's own standard focus ring. |
| Loading | Not applicable: the source performs no asynchronous operation and defines no loading flag, spinner, or placeholder state. |

## Accessibility

- **Role/trait**: The card itself (`DisclosureCardView`, an `NSView`) sets
  no accessibility role override — it is a plain container. The disclosure
  control is a standard `NSButton` with `bezelStyle = .disclosure`, which
  AppKit exposes with its own native disclosure-triangle accessibility
  role and behavior. `statusIcon` is explicitly given role `.image`
  (`exposes-status-as-own-accessibility-element`). `titleField`,
  `subtitleField`, and `summaryField` are plain
  `NSTextField(labelWithString:)` instances with no role override, so
  AppKit's default static-text exposure applies to each.
- **Label requirements**: The disclosure control's accessibility label is
  set to `"Show details"`/`"Hide details"` at construction
  (`labels-disclosure-control`). `statusIcon`'s accessibility label is
  `status.accessibilityLabel`, doubling as its tooltip. `titleField`,
  `subtitleField`, and `summaryField` carry no separate accessibility
  label; their `stringValue`/`attributedStringValue` is what VoiceOver
  reads, per AppKit's default label exposure.
- **Announce state changes**: The disclosure control's `toolTip` and
  accessibility label are fixed at construction to the `isCollapsed` value
  passed into `init` and are never reassigned by `disclosureTapped` (see
  `does-not-self-mutate-on-toggle`). AppKit's `NSButton` still flips the
  control's own visual `state` (and its native disclosure-triangle
  accessibility value) immediately on click, so between a tap and the
  host's rebuild the tooltip/label text can read stale relative to the
  triangle's own state — this is resolved by the intended integration
  pattern (the host rebuilds the card on every toggle; see Design
  Decisions), not by anything internal to this file.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven composition; the disclosure control is a standard
  `NSButton` at its default `controlSize` with no explicit width/height
  override in source, so its click target is whatever AppKit's system
  disclosure control natively provides. The 44×44pt minimum is iOS/touch
  guidance, not a macOS pointer-interface requirement.
- **Minimum contrast ratio**: NEEDS REVIEW: Not implemented in source. All
  colors are drawn from a `SemanticPalette` (`surfaceColor`/
  `outlineColor`/`primaryTextColor`/etc.), and no numeric contrast check is
  performed anywhere in `DisclosureCardView.swift`. Whether any given
  theme's title-on-titlebar, subtitle-on-surface, or summary-value-on-
  surface pairing meets a specific ratio (e.g. WCAG 2.1 AA's 4.5:1) cannot
  be determined from this file alone — it depends on the actual color
  values each `SemanticPalette`/theme resolves, which live outside this
  source. This would be settled by auditing each shipped theme's resolved
  colors for these role pairings.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| disclosure-card-001 | renders-card-as-rounded-bordered-surface | Any `init(...)` call | `surface.layer.cornerRadius == 10`; `surface.layer.borderWidth == 1`; `surface.layer.backgroundColor == palette.surfaceColor.cgColor`; `surface.layer.borderColor == palette.outlineColor.cgColor` |
| disclosure-card-002 | clips-titlebar-to-card-corners | Any `init(...)` call | `surface.layer.masksToBounds == true` |
| disclosure-card-003 | renders-titlebar-as-elevated-strip | Any `init(...)` call | `titlebar.layer.backgroundColor == palette.elevatedSurfaceColor.cgColor` |
| disclosure-card-004 | draws-titlebar-rule | Any `init(...)` call | `titlebarRule.layer.backgroundColor == palette.dividerColor.cgColor`; rule height constraint equals 1pt and spans the titlebar's width |
| disclosure-card-005 | sizes-titlebar-to-header-plus-inset | Card at a given `scaledSize` | `titlebar`'s height equals the header row's fitting height plus `padTitleY` |
| disclosure-card-006 | draws-badge-above-surface-border | Card constructed with a non-nil `status` | `statusIcon` appears later in `subviews` than `surface`, and renders visually above the surface's border in a snapshot |
| disclosure-card-007 | allows-badge-to-render-outside-frame | Any `init(...)` call | `clipsToBounds == false` on the card |
| disclosure-card-008 | displays-title-text | `init(title: "mike@example.com", ...)` | `titleField.stringValue == "mike@example.com"` |
| disclosure-card-009 | truncates-title-in-middle | `titleField.lineBreakMode` inspected on any instance | Equals `.byTruncatingMiddle` |
| disclosure-card-010 | yields-title-width-first | Any instance | `titleField`/`titleLine` compression-resistance and hugging priorities (horizontal) equal `.defaultLow`, lower than `trailingLine`'s `.required` |
| disclosure-card-011 | colors-title-by-accent-flag | `init(..., titleIsAccent: true, ...)` vs. `false` | `titleField.textColor == palette.accentColor` when `true`; `== palette.primaryTextColor` when `false` |
| disclosure-card-012 | sets-title-font-semibold-body | Theme applied at a given `scaledSize` | `titleField.font` matches `.body` style at `scaledSize` with `.semibold` weight |
| disclosure-card-013 | places-title-accessory-leading | `init(..., titleAccessory: someView, ...)` | `titleLine.arrangedSubviews == [someView, titleField]`; spacing `== 6`; `someView`'s horizontal compression resistance is `.required` |
| disclosure-card-014 | places-titlebar-accessory-before-disclosure | `init(..., titlebarAccessory: someView, ...)` | `trailingLine.arrangedSubviews == [someView, disclosure]`; spacing `== 6` |
| disclosure-card-015 | never-shrinks-trailing-line | Any instance | `trailingLine`'s horizontal compression-resistance and hugging priorities both equal `.required` |
| disclosure-card-016 | maintains-minimum-header-gap | Card narrowed until title and trailing line compete for space | The gap between `titleLine.trailingAnchor` and `trailingLine.leadingAnchor` is never less than 8pt; the two lines share a common center-Y |
| disclosure-card-017 | renders-native-disclosure-control | Any instance | `disclosure` is an `NSButton` with `bezelStyle == .disclosure` and `buttonType == .onOff` |
| disclosure-card-018 | sets-disclosure-initial-state | `init(..., isCollapsed: true, ...)` vs. `false` | `disclosure.state == .off` when `true`; `== .on` when `false` |
| disclosure-card-019 | labels-disclosure-control | `init(..., isCollapsed: true, ...)` vs. `false` | `disclosure.toolTip` and accessibility label equal `"Show details"` when `true`; `"Hide details"` when `false` |
| disclosure-card-020 | forwards-toggle-state | Click `disclosure` on a card constructed `isCollapsed: false` | `onToggle` is called once with `true` (button's new state is `.off`) |
| disclosure-card-021 | does-not-self-mutate-on-toggle | Click `disclosure` on any card, inspect the same instance immediately after | `content.isHidden`, `body.isHidden`, `subtitleField.isHidden`, and `disclosure.toolTip` are all unchanged from their pre-click values |
| disclosure-card-022 | hides-content-when-collapsed | `init(..., isCollapsed: true, ...)` vs. `false` | `content.isHidden == true` when `true`; `== false` when `false` |
| disclosure-card-023 | builds-content-regardless-of-fold-state | `addContent(someView)` on a card constructed `isCollapsed: true` | `content.arrangedSubviews` includes `someView` even though `content.isHidden == true` |
| disclosure-card-024 | forces-subtitle-hidden-when-collapsed | `init(..., subtitle: "note", isCollapsed: true, ...)` | `subtitleField.isHidden == true` |
| disclosure-card-025 | hides-subtitle-when-absent | `init(..., subtitle: nil, isCollapsed: false, ...)` | `subtitleField.isHidden == true` |
| disclosure-card-026 | detaches-empty-body | `init(..., subtitle: nil, summary: [], isCollapsed: true, ...)` | `body.isHidden == true` |
| disclosure-card-027 | matches-bottom-inset-to-empty-body | Same construction as disclosure-card-026 | The card's bottom constraint constant equals `-padTitleY`, not `-padY` |
| disclosure-card-028 | shows-summary-only-when-collapsed-and-present | Four combinations of `isCollapsed` × `summary.isEmpty` | `summaryField.isHidden == false` only for `(isCollapsed: true, summary: non-empty)`; `true` for the other three combinations |
| disclosure-card-029 | right-aligns-and-clips-summary-text | Any instance | `summaryField.alignment == .right`; `summaryField.lineBreakMode == .byClipping`; horizontal compression resistance `.required` |
| disclosure-card-030 | formats-summary-parts | `summary: [SummaryPart(name: "5H", value: "23%", colorName: "red")]` | `summaryField.attributedStringValue` contains `"5H: "` in caption font/`tertiaryTextColor` followed by `"23%"` in code font/`dangerColor` (via `color(named: "red")`) |
| disclosure-card-031 | separates-summary-parts | `summary` with two `SummaryPart`s | `summaryField.attributedStringValue` contains exactly one `"  |  "` run, positioned between the two parts, styled like a summary name |
| disclosure-card-032 | hides-status-badge-when-absent | `init(..., status: nil, ...)` | `statusIcon.isHidden == true` |
| disclosure-card-033 | renders-status-as-sf-symbol | `init(..., status: StatusSymbol(symbolName: "exclamationmark.triangle.fill", colorName: "yellow", accessibilityLabel: "Warning"), ...)` | `statusIcon.image` is a valid SF Symbol image named `"exclamationmark.triangle.fill"`; `statusIcon.symbolConfiguration.weight == .semibold` |
| disclosure-card-034 | exposes-status-as-own-accessibility-element | Same construction as disclosure-card-033 | `statusIcon.isAccessibilityElement() == true`; `statusIcon.accessibilityRole() == .image`; `statusIcon.accessibilityLabel() == "Warning"`; `statusIcon.toolTip == "Warning"` |
| disclosure-card-035 | colors-status-badge | `status.colorName: nil` vs. `"blue"` | `statusIcon.contentTintColor == palette.secondaryTextColor` when `nil`; `== palette.accentColor` when `"blue"` (per `color(named:)`'s name→role map) |
| disclosure-card-036 | positions-badge-on-visible-corner | Any instance with a non-nil `status` | `statusIcon.centerXAnchor == trailingAnchor - cornerPeakInset`; `statusIcon.centerYAnchor == topAnchor + cornerPeakInset`, where `cornerPeakInset ≈ 2.93` |
| disclosure-card-037 | sizes-badge-diameter | `scaledSize == 13` | `statusIcon` width and height both equal `min(ceil(13 × 1.3), padXFor(13) × 1.5)` |
| disclosure-card-038 | dims-whole-card-uniformly | `init(..., isDimmed: true, ...)` vs. `false` | `view.alphaValue == 0.55` when `true`; `== 1.0` when `false` |
| disclosure-card-039 | scales-insets-with-text-size | `scaledSize == 26` (2× the 13pt baseline) | `padX == ceil(14 × 26 / 13) == 28`; `padMastheadX == ceil(7 × 26 / 13) == 14`; `padY == ceil(12 × 26 / 13) == 24`; `padTitleY == ceil(6 × 26 / 13) == 12` |
| disclosure-card-040 | floors-width-to-wider-of-open-or-folded-content | Card with wide `content` and a non-empty `summary`, both open and folded | `contentWidthFloor.constant` is identical whether `isCollapsed` is `true` or `false`, and equals the wider of the two rows plus `padMastheadX + padX` |
| disclosure-card-041 | keeps-width-floor-just-under-required | Any instance | `contentWidthFloor.priority.rawValue == 999` |
| disclosure-card-042 | remeasures-width-floor-on-layout | Font/theme change that widens hidden `content` after initial layout, followed by a `layout()` pass | `contentWidthFloor.constant` updates to the new wider value; a follow-up `layout()` pass with no further change does not reassign the constant (change is `<= 0.5pt`) |
| disclosure-card-043 | applies-theme-immediately-and-on-change | Construct a card, then trigger a theme change | `applyTheme(_:)` runs once synchronously at construction and again after the theme change, updating colors/fonts both times |
| disclosure-card-044 | rejects-storyboard-instantiation | `DisclosureCardView(coder:)` invoked (e.g. via nib/storyboard unarchiving) | Process traps with a fatal error |
| disclosure-card-045 | confines-mutation-to-main-actor | Attempt to call `DisclosureCardView.init`/`addContent`/`contentSpacing` from a non-main-actor context | Code does not compile (Swift concurrency checker rejects the call) |
| disclosure-card-046 | exposes-content-spacing | `card.contentSpacing = 20` | `content.spacing == 20`; `contentWidthFloor` is re-measured against the new spacing |

`prefers-dynamic-summary-colors` has no test vector: it constrains what
`SummaryPart.color` closures callers choose to write, not an observable
behavior of `DisclosureCardView` itself (see Design Decisions).

## Edge Cases

- **Empty `title`** (`""`): renders with no guard against it — `titleField`
  displays an empty string and the header row lays out with a zero-width
  title (MUST, per `displays-title-text` — the source has no empty-string
  check).
- **Very long `title` with no accessories**: truncated in the middle rather
  than the tail or head (MUST, per `truncates-title-in-middle`); the
  required minimum header gap and the trailing line's required compression
  resistance keep the disclosure control fully visible regardless of title
  length (MUST, per `maintains-minimum-header-gap` and
  `never-shrinks-trailing-line`).
- **`summary` non-empty while `isCollapsed == false` at construction**: the
  summary row itself stays hidden (per `shows-summary-only-when-collapsed-
  and-present`), but `mastheadWidthFloor` is still computed from `summary`
  in `applyTheme(_:)` regardless of `isCollapsed`, so an initially-open
  card's width floor already reserves room for the summary line it would
  show if folded (MUST, per `floors-width-to-wider-of-open-or-folded-
  content`).
- **`summary` empty and `isCollapsed == true`**: the card renders as
  exactly its titlebar, with `body` fully detached and the bottom inset
  switched to `padTitleY` (MUST, per `detaches-empty-body` and
  `matches-bottom-inset-to-empty-body`).
- **`status.symbolName` does not resolve to a valid SF Symbol**:
  `NSImage(systemSymbolName:accessibilityDescription:)` returns `nil` and
  is assigned to `statusIcon.image` with no fallback or guard — the badge's
  frame, position, and accessibility label/tooltip are still fully
  configured, but no image paints (MUST, per `renders-status-as-sf-symbol`
  — the source performs no validation of `symbolName`).
- **Extreme `scaledSize` values** (very small, e.g. approaching 0, or very
  large, e.g. an accessibility "larger text" size well above the 13pt
  baseline): every inset and font scales linearly and is rounded up via
  `ceil`, with no minimum clamp — an extremely small `scaledSize` can drive
  insets toward 0pt. The status badge diameter is the one value with an
  explicit upper bound (`min(ceil(scaledSize × 1.3), padXFor(scaledSize) ×
  1.5)`); every other scaled constant is otherwise unbounded above (MUST,
  per `scales-insets-with-text-size` and `sizes-badge-diameter`).
- **Concurrent access**: Not applicable — the class and its public API are
  `@MainActor`-isolated; the Swift compiler rejects construction or
  mutation from off the main actor, so there is no concurrent-access
  surface for this component to define behavior for.
- **Error states (dependency/network failure)**: Not applicable — the
  source performs no network call, database access, or file-system I/O of
  any kind.
- **Offline/disconnected state**: Not applicable — `DisclosureCardView`
  has no networking dependency of its own.
- **Boundary values**: `cornerRadius`, `borderWidth`, `horizontalInset`,
  `verticalInset`, `titlebarInset`, `mastheadInset`, `iconGap`,
  `dimmedAlpha`, and `mastheadGap` are fixed literals, not caller-
  configurable ranges with a boundary to test. `scaledSize` is the one
  caller-configurable numeric input; its boundary behavior is covered
  above under "Extreme `scaledSize` values."

## Configuration

`DisclosureCardView` (`packages/apple/AgenticToolkit/macOS/UI/Cards/DisclosureCardView.swift`):

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `title` | `String` | — (required) | Text shown in the titlebar |
| `titleIsAccent` | `Bool` | — (required) | Colors `title` with `accentColor` when `true`, `primaryTextColor` when `false` |
| `titleAccessory` | `NSView?` | `nil` | View placed before the title, e.g. a host's logo mark |
| `titlebarAccessory` | `NSView?` | `nil` | View placed before the disclosure control, e.g. a per-card menu |
| `subtitle` | `String?` | `nil` | One quiet line under the masthead; hidden whenever the card is collapsed |
| `summary` | `[SummaryPart]` | `[]` | Readings shown on their own right-aligned line only while the card is collapsed |
| `status` | `StatusSymbol?` | `nil` | Symbol stamped on the card's top-right corner |
| `isCollapsed` | `Bool` | `false` | Whether the card is constructed folded; fixed for the instance's lifetime |
| `isDimmed` | `Bool` | `false` | Whether the whole card renders at reduced (0.55) alpha |
| `scaledSize` | `CGFloat` | — (required) | The text size driving every scaled inset, font, and badge dimension |
| `onToggle` | `((Bool) -> Void)?` | `nil` | Called with the requested new collapsed state when the disclosure control is tapped |

`SummaryPart`:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `name` | `String` | — (required) | The reading's label, e.g. `"5H"` |
| `value` | `String` | — (required) | The reading's value, e.g. `"23%"` |
| `color` | `(SemanticPalette) -> NSColor?` | — (required, or derived from `colorName`) | Resolves the value's color against the live palette each time it is called |
| `colorName` (convenience `init`) | `String?` | — | Looked up via `palette.color(named:)` in place of a custom `color` closure |

`StatusSymbol`:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `symbolName` | `String` | — (required) | SF Symbol name rendered in the corner badge |
| `colorName` | `String?` | — (required) | Looked up via `palette.color(named:)`; falls back to `secondaryTextColor` when `nil` or unresolved |
| `accessibilityLabel` | `String` | — (required) | Used as both the badge's accessibility label and its tooltip |

Public API beyond `init`:

```swift
public func addContent(_ view: NSView)
public var contentSpacing: CGFloat { get set }
public var isCollapsed: Bool { get }
```

## Deep Linking

Not applicable: `DisclosureCardView` is a display/layout `NSView` subclass
with no route, URL scheme handling, or navigable identity anywhere in the
source.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded literal) | `Show details` | Disclosure control's `toolTip` and accessibility label when constructed `isCollapsed: true` |
| (none — hardcoded literal) | `Hide details` | Disclosure control's `toolTip` and accessibility label when constructed `isCollapsed: false` |

`title`, `subtitle`, `summary`'s `name`/`value` strings, and
`status.accessibilityLabel` are all caller-supplied at the call site — the
component defines no string literals of its own for them. The two disclosure
strings above ARE component-owned literals, and the source assigns them
directly (`"Show details"`/`"Hide details"`) with no `NSLocalizedString` or
string-catalog key — a real localization gap for a component intended to
ship in a localized app, documented here rather than smoothed over.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the source performs no animation, transition, or `NSAnimationContext`/`CATransaction` call anywhere — every state change (theme colors, fonts, the width floor) is an instantaneous property or constraint-constant assignment. |
| Increase Contrast | Not applicable to this component directly: the source reads no system contrast setting; every color it draws comes from the active `SemanticPalette`, and whether the resulting contrast is sufficient is tracked once under Accessibility above, not duplicated here. |
| Differentiate Without Color | Satisfied: the disclosure state is communicated by the triangle's own orientation plus its tooltip/label text, not color; the status badge pairs its tint with a distinct SF Symbol shape and an `accessibilityLabel`; and every summary value is always paired with its `name` text label (`formats-summary-parts`) rather than color alone. |

## Feature Flags

Not applicable: the source contains no feature-flag reads. The card renders
unconditionally whenever it is constructed.

## Analytics

Not applicable: the source contains no analytics, tracking, or telemetry
call.

## Privacy

- **Data collected**: None — the component holds only the `title`,
  `subtitle`, `summary`, `status`, and accessory values passed to it by the
  caller; it originates no data of its own.
- **Storage**: Not applicable — `DisclosureCardView` performs no
  persistence of any kind. (The companion `CardFoldMemory` type persists
  which cards are folded, but that is a separate file the host wires in;
  it is not part of this source.)
- **Transmission**: Not applicable — the source performs no network I/O.
- **Retention**: Not applicable — the view retains only its own subviews
  and the caller-supplied values for its own instance lifetime.

## Logging

Not applicable: the source contains no logging call (no `os_log`, `Logger`,
or `print`).

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
  `Modifier.align(Alignment.TopEnd)` and a small negative offset.
- **React/Web**: A `<details>`/`<summary>`-style component (or a `<div>`
  with `aria-expanded`) whose header renders with the elevated background
  and a rotating disclosure `<button>`; the body toggles via a CSS class
  rather than `display: none` when the collapsed one-line summary must
  still show. Reserve the width floor by measuring both the open and
  collapsed header/body with `ResizeObserver` (or by rendering both
  off-screen with `visibility: hidden` rather than `display: none`, which
  is what keeps AppKit's `isHidden` measurable and CSS `display: none`
  is not). Position the status badge with `position: absolute;
  top: <peak>px; right: <peak>px; transform: translate(50%, -50%)`.
- **AppKit / UIKit** (source platform): Source at
  `packages/apple/AgenticToolkit/macOS/UI/Cards/DisclosureCardView.swift`
  (this recipe's source), plus its directory-mates `PinnedEndsLine.swift`
  (the header row's pinned-ends layout), `NSStackView+FullWidth.swift`
  (`addFullWidthArrangedSubview`, used to make `body`'s rows fill the
  stack's width), and `CardFoldMemory.swift` (the host-side persistence and
  rebuild helper most callers wire this view to). This is macOS-only —
  `NSView`/`NSButton`/`NSStackView`/`NSTextField`/`NSImageView`; there is no
  UIKit code path in source. A UIKit port would replace those with
  `UIView`/a custom disclosure `UIButton` (UIKit has no built-in disclosure-
  triangle bezel style)/`UIStackView`/`UILabel`/`UIImageView`, and would
  need to re-derive the fold-independent width floor manually, since
  `UIStackView.isHidden` — like `NSStackView.isHidden` — detaches a hidden
  arranged view from layout but still allows measuring its `intrinsicContentSize`
  when asked directly.
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
  `-cornerPeakInset` on the top and right edges and `HorizontalAlignment /
  VerticalAlignment="Right"/"Top"`, with `Canvas.ZIndex` (or simple
  z-order in the `Grid`'s children) set above the `Border` that draws the
  card's own `BorderBrush`/`BorderThickness`, matching
  `draws-badge-above-surface-border`.

## Design Decisions

- **Decision**: `disclosureTapped` only calls `onToggle`; it never mutates
  `content.isHidden`, `body.isHidden`, or the disclosure control's own
  tooltip/label.
  **Rationale**: Per the type's own doc comment, "a fold is applied by
  rebuilding, not by mutating" — the public `isCollapsed` is a `get`-only
  property backed by `content.isHidden`, fixed at `init`. The intended
  integration (`CardFoldMemory.setCollapsed`) records the new state and
  rebuilds the card on the next runloop turn, specifically because a
  synchronous rebuild would tear down the very button whose click is still
  dispatching.
  **Approved: pending**
- **Decision**: The width floor is computed as the wider of the open
  content's fitting width and the folded masthead's width, and is
  recomputed on every `layout()` pass regardless of the card's current
  fold state.
  **Rationale**: Per the type's own doc comment, "a card is exactly as wide
  folded as it is open" — a content-hugging window that re-derived its
  width from whichever state happened to be visible would jump sideways on
  every fold, which is what this fold-independent floor prevents.
  **Approved: pending**
- **Decision**: The status badge is centered on `cornerPeakInset`
  (`cornerRadius − cornerRadius/√2`), not on the frame's literal corner,
  and is added as a top-level sibling subview after `surface` rather than
  inside it.
  **Rationale**: Per the type's own doc comment, a rounded card has no ink
  at the square corner, so centering there would look like the badge
  "slipped off"; and a `CALayer` draws its own border above its sublayers,
  so the badge must live outside `surface`'s layer tree to paint above that
  border.
  **Approved: pending**
- **Decision**: Dimming is a single `alphaValue` applied to the whole view,
  not a second set of dimmed theme colors.
  **Rationale**: Per the type's own doc comment, this makes the card
  recede "complete — border, surface, content and all" while every color
  it draws keeps meaning exactly what it means on the live card.
  **Approved: pending**
- **Decision**: `titleAccessory` and `titlebarAccessory` are placed and
  measured but never styled, tinted, or given any accessibility
  configuration by `DisclosureCardView`.
  **Rationale**: Per the type's own doc comment, a host that passes a view
  has already decided its appearance and behavior; recoloring or otherwise
  opinionating on it would fight a caller that, for example, hands in a
  logo that is also a button.
  **Approved: pending**
- **Decision**: The disclosure control's `toolTip`/accessibility label
  strings (`"Show details"`, `"Hide details"`) are English literals with no
  localization key.
  **Rationale**: Documented here rather than idealized away — the source
  has no string-catalog or `NSLocalizedString` call for these two strings,
  unlike every other piece of text on the card, which is entirely
  caller-supplied.
  **Approved: pending**

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | needs-review | accessibility |
| [differentiate-without-color](agenticdevelopercookbook://compliance/accessibility#differentiate-without-color) | passed | accessibility |
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [main-actor-confined](agenticdevelopercookbook://compliance/architecture#main-actor-confined) | passed | architecture |
| [theme-driven-typography](agenticdevelopercookbook://compliance/ui-tokens#theme-driven-typography) | passed | ui-tokens |
| [no-raw-hex](agenticdevelopercookbook://compliance/ui-tokens#no-raw-hex) | passed | ui-tokens |

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial recipe — extracted from the Apple `DisclosureCardView` (AppKit, macOS) source. |
