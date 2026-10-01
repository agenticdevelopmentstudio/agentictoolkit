---
id: d5aba939-471d-48cd-9a9c-888ac92adf38
title: Disclosure Card View
domain: agentictoolkit://cookbook/ui/containers/disclosure-card-view
type: ingredient
version: 1.3.0
status: review
language: en
created: '2026-09-23'
modified: '2026-10-01'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Foldable card with an elevated titlebar, a native disclosure control, a
  collapsed summary line, and a corner status badge.
platforms:
- swift
- macos
tags:
- card
- disclosure
- collapsible
depends-on: []
related:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

# Disclosure Card View

## Overview

A foldable card: a rounded, bordered surface with an elevated titlebar strip
naming it (a title, an optional leading accessory, an optional status
symbol right after the title, an optional trailing accessory, and a native
disclosure control), and whatever host content is
added beneath that. Folding the card hides its content and, if the card
carries `summary` readings, shows a single right-aligned line of them under
the title instead; a folded card with no summary is exactly its titlebar and
nothing else. The card can also show one status badge stamped on its
top-right corner. Its own width never changes between open and folded
states, because both states' content is measured and the wider is reserved
regardless of which is currently drawn. Activating the disclosure control
does not fold the card itself — it reports the requested new state through a
toggle callback and leaves layout untouched; the host is expected to rebuild
the card with a new `isCollapsed` value (typically via a companion
fold-memory helper that persists the folded set and rebuilds on toggle).

## Behavioral Requirements

- **renders-card-as-rounded-bordered-surface**: Component MUST render its
  background as a rounded, bordered surface pinned to all four edges of the
  card, with a 10pt corner radius, a 1pt border, a background of the
  palette's `surfaceColor`, and a border color of the palette's
  `outlineColor`.
- **clips-titlebar-to-card-corners**: Component MUST clip the titlebar strip
  to the card's rounded corners, so the strip's own square top corners never
  draw past the card's curve.
- **renders-titlebar-as-elevated-strip**: Component MUST fill the titlebar
  strip with the palette's `elevatedSurfaceColor`, distinct from the card
  body's `surfaceColor`.
- **draws-titlebar-rule**: Component MUST draw a 1pt hairline along the
  titlebar's bottom edge, filled with the palette's `dividerColor` and
  spanning the titlebar's full leading-to-trailing width.
- **sizes-titlebar-to-header-plus-inset**: Component MUST size the titlebar
  strip's height to the header row's (title row plus trailing row) height
  plus the titlebar's own vertical inset (`padTitleY`, see Appearance) below
  it, never to the body section's height.
- **draws-badge-above-surface-border**: Component MUST add the status badge
  as a sibling view added after the card surface, so it paints above the
  surface's own border, which the surface's own rendering layer otherwise
  draws above all of that layer's nested content.
- **allows-badge-to-render-outside-frame**: Component MUST NOT clip its own
  contents to its bounds, so the status badge can be drawn partially outside
  the card's own frame.
- **displays-title-text**: Component MUST display the exact `title` string
  it was constructed with as the titlebar's title text.
- **truncates-title-in-middle**: Component MUST truncate the title text in
  the middle when it does not fit the available width.
- **yields-title-width-first**: Component MUST make the title text and its
  row the first element on the header row to shrink when space is tight, and
  MUST NOT let it grow to claim more width than its own text needs.
- **colors-title-by-accent-flag**: Component MUST color the title text with
  the palette's `accentColor` when `titleIsAccent == true`, and with
  `primaryTextColor` otherwise.
- **sets-title-font-semibold-body**: Component MUST set the title text's
  font to the palette's `.body` typography style with its weight overridden
  to semibold, resolved to a font at `scaledSize`.
- **places-title-accessory-leading**: When `titleAccessory` is non-nil,
  Component MUST place it immediately before the title text inside the
  title row, separated by the icon gap (`iconGap`, 6pt unscaled), and MUST
  hold the accessory at its natural width so only the title text — never
  the accessory — yields width.
- **places-title-status-after-title**: When `titleTrailingStatus` is
  non-nil, Component MUST draw it immediately after the title text inside
  the title row, separated by the icon gap, as a symbol icon named by
  `titleTrailingStatus.symbolName` drawn at a semibold weight at a size of
  `scaledSize` (the title's own size), and MUST hold it at its natural
  width, so only the title text — never the symbol — yields width.
  Component MUST NOT add anything after the title when
  `titleTrailingStatus` is `nil`.
- **exposes-title-status-like-badge**: For a `titleTrailingStatus` that is
  not a placeholder, Component MUST expose the symbol as its own
  accessibility element with an image accessibility role and accessibility
  label `titleTrailingStatus.accessibilityLabel`, and MUST set that same
  string as its tooltip.
- **reserves-placeholder-room-silently**: For a `titleTrailingStatus` made
  by `StatusSymbol.placeholder(sizedLike:)`, Component MUST keep exactly
  the room the named symbol would take in the title row — drawn fully
  transparent (opacity 0), never hidden, since a hidden element is given
  no room in the row — and MUST NOT expose it as an accessibility element
  or give it a tooltip.
- **asks-for-whole-point-title-width**: Component MUST report the title
  text's natural width rounded up to a whole point, so the width the
  card's floor measures for the title and the width the title is laid out
  at agree, and a title never truncates in a card given exactly its own
  fitting width.
- **places-titlebar-accessory-before-disclosure**: When `titlebarAccessory`
  is non-nil, Component MUST place it immediately before the disclosure
  control inside the trailing row, separated by the icon gap.
- **never-shrinks-trailing-line**: Component MUST hold the trailing row (the
  titlebar accessory, if any, plus the disclosure control) at its natural
  width and MUST NOT let it grow beyond that, so it never yields width to
  the title row.
- **maintains-minimum-header-gap**: Component MUST keep at least the
  masthead gap (`mastheadGap`, `ceil(24 × scaledSize / baseFontSize)`, see
  Appearance) between the title row's trailing edge and the trailing row's
  leading edge, and MUST vertically center-align the two rows on the header
  row.
- **renders-native-disclosure-control**: Component MUST render the fold
  control as the platform's native disclosure control, rather than a
  custom-drawn chevron.
- **sets-disclosure-initial-state**: Component MUST set the disclosure
  control's indicator to its closed position when constructed with
  `isCollapsed == true`, and to its open position when constructed with
  `isCollapsed == false`.
- **labels-disclosure-control**: Component MUST set the disclosure
  control's tooltip and accessibility label to `"Show details"` when
  constructed with `isCollapsed == true`, and to `"Hide details"` when
  constructed with `isCollapsed == false`.
- **forwards-toggle-state**: Component MUST invoke the toggle callback,
  passing `true` when the disclosure control's indicator becomes closed and
  `false` when it becomes open, whenever the user activates the disclosure
  control.
- **does-not-self-mutate-on-toggle**: Component MUST NOT change the content
  area's visibility, the body section's visibility, subtitle visibility, or
  the disclosure control's own tooltip/accessibility label as a direct
  result of activating the disclosure control — activating it only invokes
  the toggle callback. Folding is applied only by the host reconstructing
  the view with a new `isCollapsed` (see Design Decisions).
- **hides-content-when-collapsed**: Component MUST hide the content area for
  the lifetime of an instance constructed with `isCollapsed == true`, and
  show it for one constructed with `isCollapsed == false`.
- **builds-content-regardless-of-fold-state**: Component MUST add every
  view passed to the content-adding operation to the content area
  regardless of the card's current fold state, so a folded card's content
  remains measurable.
- **forces-subtitle-hidden-when-collapsed**: Component MUST hide the
  subtitle text when constructed with `isCollapsed == true`, even when a
  non-nil `subtitle` was supplied.
- **hides-subtitle-when-absent**: Component MUST hide the subtitle text when
  `subtitle == nil`.
- **detaches-empty-body**: Component MUST hide the entire body section
  (summary row, subtitle, and content) when constructed with
  `isCollapsed == true` and an empty `summary`, so the card renders as
  exactly its titlebar with no residual empty space beneath it.
- **matches-bottom-inset-to-empty-body**: Component MUST use the titlebar's
  own vertical inset (`padTitleY`), not the larger body inset (`padY`), as
  its own bottom inset when the body section is hidden, so a titlebar-only
  card's bottom edge sits `padTitleY` under the header, matching the
  header's own top inset.
- **shows-summary-only-when-collapsed-and-present**: Component MUST show
  the summary line only when constructed with `isCollapsed == true` AND a
  non-empty `summary`; it MUST be hidden in every other combination of
  those two inputs.
- **right-aligns-and-clips-summary-text**: Component MUST right-align the
  summary line's text, hold it at its natural width, and clip rather than
  truncate-with-ellipsis if the reserved width is ever exceeded.
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
- **hides-status-badge-when-absent**: Component MUST hide the status badge
  when `status == nil`.
- **renders-status-as-symbol-icon**: Component MUST render a non-nil
  `status` as a symbol icon named by `status.symbolName`, sized to the
  status badge's diameter for the current `scaledSize` (see
  `sizes-badge-diameter`) and drawn at a semibold weight, with
  `status.accessibilityLabel` as its accessibility description. An
  unresolvable symbol name yields a blank image rather than no image (see
  Edge Cases).
- **exposes-status-as-own-accessibility-element**: Component MUST expose
  the status badge as its own accessibility element with an image
  accessibility role and accessibility label `status.accessibilityLabel`,
  and MUST set that same string as its tooltip.
- **colors-status-badge**: Component MUST tint the status badge with
  `status.color(palette)` and the title status symbol with
  `titleTrailingStatus.color(palette)`, each asked of the live palette on
  every theme application and each falling back to `secondaryTextColor`
  whenever it returns `nil` (including when the `StatusSymbol` itself is
  `nil`, or was built with a `nil` `colorName`).
- **positions-badge-on-visible-corner**: Component MUST center the status
  badge, on both axes, `cornerPeakInset` (`cornerRadius − cornerRadius/√2`,
  ≈2.93pt at the fixed 10pt radius) inside the card's top-right corner —
  the point where the rounded corner's arc actually turns — not on the
  frame's literal square corner.
- **sizes-badge-diameter**: Component MUST size the status badge to
  `min(ceil(scaledSize × 1.3), padX × 1.5)` on each axis (see Appearance for
  `padX`).
- **dims-whole-card-uniformly**: Component MUST set the entire view's
  opacity to 0.55 when constructed with `isDimmed == true`, and to `1.0`
  otherwise, rather than substituting a separate set of dimmed colors.
- **scales-insets-with-text-size**: Component MUST scale
  `horizontalInset` (14), `mastheadInset` (7), `verticalInset` (12),
  `titlebarInset` (6), and the masthead gap (`mastheadGapAtSystemSize`, 24)
  linearly by `scaledSize ÷ baseFontSize` (the
  platform's own base system font size), rounding each result up, rather
  than using fixed point values.
- **floors-width-to-wider-of-open-or-folded-content**: Component MUST
  constrain its own width to be greater than or equal to the wider of (a)
  the content area's fitting width and (b) the masthead's folded-state
  width (the title-row-plus-trailing-row line, or the summary line,
  whichever is wider) — plus the masthead's leading gutter (`padMastheadX`)
  and trailing gutter (`padX`) — regardless of whether the card is
  currently open or folded, and whether or not it has a `summary`: a card
  with no summary still asks for the room to write its title whole.
- **keeps-width-floor-just-under-required**: Component MUST set the
  width-floor constraint's priority just under the layout system's
  required priority (specifically 999), so a container too narrow for the
  content scrolls rather than making the layout unsatisfiable.
- **remeasures-width-floor-on-layout**: Component MUST recompute its width
  floor on every layout pass, but MUST only apply the newly computed
  constant when it differs from the current one by more than 0.5pt.
- **applies-theme-immediately-and-on-change**: Component MUST apply the
  current theme once at construction and again on every subsequent theme
  change.
- **exposes-content-spacing**: Component MUST expose a `contentSpacing`
  property that reads and writes the content area's spacing, and MUST
  re-measure the width floor whenever it is set.

## Appearance

- **Corner radius**: 10pt, fixed (`cornerRadius`); unaffected by
  `scaledSize`.
- **Padding**: `padX` = `ceil(14 × scaledSize / baseFontSize)`, the
  card's trailing gutter — from the card edge to body/content rows and to
  the summary/subtitle's trailing edge; `padMastheadX` =
  `ceil(7 × scaledSize / baseFontSize)`, the masthead's own
  leading gutter — from the card edge to the masthead line's leading edge;
  `padY` = `ceil(12 × scaledSize / baseFontSize)` as the card's own
  bottom inset when the body section is present; `padTitleY` =
  `ceil(6 × scaledSize / baseFontSize)` as the titlebar's own
  top/bottom inset, and as the card's bottom inset when the body section is
  hidden; `iconGap` = 6pt fixed between an accessory or the title status
  symbol and the text/control beside it; `mastheadGap` =
  `ceil(24 × scaledSize / baseFontSize)` minimum between the title row and
  the trailing row. The masthead's own width floor (below) reserves
  `padMastheadX` on its leading side and `padX` on its trailing side — the
  same two gutters the card itself is pinned at.
- **Corner peak inset**: `cornerPeakInset` = `cornerRadius − cornerRadius/√2`
  (≈2.93pt at the fixed 10pt `cornerRadius`) — the distance in from the
  frame's literal corner, on both axes, to the point where the rounded
  corner's arc actually turns — what the status badge is centered on.
- **Badge diameter**: `min(ceil(scaledSize × 1.3), padX × 1.5)` — the status
  badge's width and height at a given `scaledSize`.
- **Title status symbol**: drawn at a size of `scaledSize`, semibold
  weight — the title's own size, since it reads as part of the name — at
  its natural size, with no fixed frame of its own.
- **Masthead width floor**: for every card, the wider of (a) the title
  row's fitting width (leading accessory, whole-point title width, and
  title status symbol or placeholder included) plus `mastheadGap` plus the
  trailing row's fitting width, and (b) the summary line's rendered text
  width when `summary` is non-empty, `0` when it is empty. Feeds `floors-width-to-wider-of-open-or-folded-
  content`.
- **Font**: title — palette `.body` style, weight forced to semibold, at
  `scaledSize`; subtitle and summary names — palette `.caption` style at
  `scaledSize × 0.85`; summary values — palette `.code` style at
  `scaledSize × 0.85`.
- **Background**: card body — palette `surfaceColor`; titlebar strip —
  palette `elevatedSurfaceColor`.
- **Foreground/Text**: title — `accentColor` when `titleIsAccent`,
  otherwise `primaryTextColor`; subtitle, summary names, and the summary
  separator — `tertiaryTextColor`; summary values — each `SummaryPart`'s
  own resolved color, falling back to `secondaryTextColor`; disclosure
  control tint — `secondaryTextColor`; status badge tint —
  `status.color(palette)`, and title status symbol tint —
  `titleTrailingStatus.color(palette)`, each falling back to
  `secondaryTextColor`.
- **Border**: card surface — 1pt, palette `outlineColor`; titlebar rule —
  1pt, palette `dividerColor` (a filled strip along the titlebar's bottom
  edge, not a stroked border).
- **Shadow**: none — no shadow effect (color, radius, or opacity) is
  applied to any layer of the card.
- **Min/Max size**: none declared as fixed constants. The card's only size
  constraint is the dynamic width-floor constraint (priority 999) described
  above; no explicit minimum or maximum height, and no upper bound on
  width.

## States

| State | Appearance change |
|-------|------------------|
| Default (expanded, `isCollapsed: false`) | Titlebar strip and the full content area are drawn; subtitle text shown if `subtitle` is non-nil; summary line hidden; disclosure indicator open, tooltip/label "Hide details" |
| Collapsed (`isCollapsed: true`) | Content area hidden; subtitle text forced hidden regardless of `subtitle`; summary line shown, right-aligned, if `summary` is non-empty; if `summary` is also empty, the body section is entirely hidden and the card renders as exactly its titlebar; disclosure indicator closed, tooltip/label "Show details" |
| Dimmed (`isDimmed: true`) | Whole view opacity `= 0.55`; no separate dimmed color set is used — every color the card draws is unchanged, only faded uniformly |
| Pressed | Not applicable beyond the embedded disclosure control's own native pressed appearance: the card itself defines no separate pressed interaction or custom pressed appearance of its own. |
| Focused | Not applicable: the card itself is never focusable and draws no custom focus indicator; the only focusable subview is the disclosure control, which gets the platform's own standard focus indicator. |
| Loading | Not applicable: the component performs no asynchronous operation and defines no loading flag, spinner, or placeholder state. |

## Accessibility

- **Role/trait**: The card itself sets no accessibility role override — it
  is a plain container. The disclosure control is the platform's native
  disclosure control, which is exposed with its own native disclosure
  accessibility role and behavior. The status badge is explicitly given an
  image accessibility role (`exposes-status-as-own-accessibility-element`),
  and so is the title status symbol unless it holds a placeholder, which is
  no accessibility element at all (`exposes-title-status-like-badge`,
  `reserves-placeholder-room-silently`).
  The title, subtitle, and summary text elements carry no role override, so
  the platform's default static-text exposure applies to each.
- **Label requirements**: The disclosure control's accessibility label is
  set to `"Show details"`/`"Hide details"` at construction
  (`labels-disclosure-control`). The status badge's accessibility label is
  `status.accessibilityLabel`, doubling as its tooltip, and the title
  status symbol's is `titleTrailingStatus.accessibilityLabel`, likewise
  doubling as its tooltip; a placeholder has neither. The title, subtitle,
  and summary text elements carry no separate accessibility label; their
  displayed text is what a screen reader reads, per the platform's default
  label exposure.
- **Announce state changes**: The disclosure control's tooltip and
  accessibility label are fixed at construction to the `isCollapsed` value
  it was constructed with, and are never reassigned when the control is
  activated (see `does-not-self-mutate-on-toggle`). The platform's native
  disclosure control still flips its own visual indicator (and its native
  accessibility value) immediately on activation, so between an activation
  and the host's rebuild the tooltip/label text can read stale relative to
  the indicator's own state — this is resolved by the intended integration
  pattern (the host rebuilds the card on every toggle; see Design
  Decisions), not by anything internal to this component.
- **Minimum tap target**: Not applicable — this card is designed for a
  pointer/trackpad-driven interface; the disclosure control is the
  platform's native disclosure control at its default control size with no
  explicit width/height override, so its click target is whatever the
  platform's system disclosure control natively provides. The 44×44pt
  minimum is touch-interface guidance, not a pointer-interface requirement.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. All colors are drawn from a `SemanticPalette` (`surfaceColor`/`outlineColor`/`primaryTextColor`/etc.), and no numeric contrast check is performed anywhere in this component's implementation; whether any given theme's title-on-titlebar, subtitle-on-surface, or summary-value-on-surface pairing meets a specific ratio (e.g. WCAG 2.1 AA's 4.5:1) cannot be determined from this specification or its palette mapping alone — the actual RGBA values each shipped theme resolves for these roles live outside both, and settling this needs auditing each shipped theme's resolved colors for these role pairings.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| disclosure-card-001 | renders-card-as-rounded-bordered-surface | Any construction | The card surface's rendering layer has a corner radius of 10, a border width of 1, a background color equal to `palette.surfaceColor`, and a border color equal to `palette.outlineColor` |
| disclosure-card-002 | clips-titlebar-to-card-corners | Any construction | The card surface's rendering layer clips its contents to its own bounds |
| disclosure-card-003 | renders-titlebar-as-elevated-strip | Any construction | The titlebar strip's background color equals `palette.elevatedSurfaceColor` |
| disclosure-card-004 | draws-titlebar-rule | Any construction | The titlebar's bottom rule's color equals `palette.dividerColor`; its height constraint equals 1pt and it spans the titlebar's width |
| disclosure-card-005 | sizes-titlebar-to-header-plus-inset | Card at a given `scaledSize` | The titlebar strip's height equals the header row's fitting height plus `padTitleY` |
| disclosure-card-006 | draws-badge-above-surface-border | Card constructed with a non-nil `status` | The status badge appears later in the card's view hierarchy than the card surface, and renders visually above the surface's border in a snapshot |
| disclosure-card-007 | allows-badge-to-render-outside-frame | Any construction | The card does not clip its own contents to its bounds |
| disclosure-card-008 | displays-title-text | Constructed with `title: "mike@example.com"` | The title text reads `"mike@example.com"` |
| disclosure-card-009 | truncates-title-in-middle | The title text's truncation behavior, inspected on any instance | Truncates in the middle of the string, not at the head or tail |
| disclosure-card-010 | yields-title-width-first | Any instance | The title text and title row are the first to shrink under space pressure; the trailing row holds its natural width |
| disclosure-card-011 | colors-title-by-accent-flag | Constructed with `titleIsAccent: true` vs. `false` | The title text's color `== palette.accentColor` when `true`; `== palette.primaryTextColor` when `false` |
| disclosure-card-012 | sets-title-font-semibold-body | Theme applied at a given `scaledSize` | The title text's font matches the `.body` style at `scaledSize` with a semibold weight |
| disclosure-card-013 | places-title-accessory-leading | Constructed with a `titleAccessory` view | The title row's arranged elements equal `[accessory, title text]`; spacing `== 6`; the accessory holds its natural width |
| disclosure-card-014 | places-titlebar-accessory-before-disclosure | Constructed with a `titlebarAccessory` view | The trailing row's arranged elements equal `[accessory, disclosure control]`; spacing `== 6` |
| disclosure-card-015 | never-shrinks-trailing-line | Any instance | The trailing row holds its natural width in both directions (never shrinks, never grows) |
| disclosure-card-016 | maintains-minimum-header-gap | Card at `scaledSize == 16` narrowed until the title and trailing rows compete for space, assuming `baseFontSize == 13` | The gap between the title row's trailing edge and the trailing row's leading edge is never less than `ceil(24 × 16 / 13) == 30`pt; the two rows share a common center-Y |
| disclosure-card-017 | renders-native-disclosure-control | Any instance | The disclosure control is the platform's native disclosure control |
| disclosure-card-018 | sets-disclosure-initial-state | Constructed with `isCollapsed: true` vs. `false` | The disclosure control's indicator is closed when `true`; open when `false` |
| disclosure-card-019 | labels-disclosure-control | Constructed with `isCollapsed: true` vs. `false` | The disclosure control's tooltip and accessibility label equal `"Show details"` when `true`; `"Hide details"` when `false` |
| disclosure-card-020 | forwards-toggle-state | Activate the disclosure control on a card constructed `isCollapsed: false` | The toggle callback is called once with `true` (the control's indicator becomes closed) |
| disclosure-card-021 | does-not-self-mutate-on-toggle | Activate the disclosure control on any card, inspect the same instance immediately after | The content area's visibility, the body section's visibility, the subtitle text's visibility, and the disclosure control's tooltip are all unchanged from their pre-activation values |
| disclosure-card-022 | hides-content-when-collapsed | Constructed with `isCollapsed: true` vs. `false` | The content area is hidden when `true`; shown when `false` |
| disclosure-card-023 | builds-content-regardless-of-fold-state | Add a content view to a card constructed `isCollapsed: true` | The content area's arranged elements include that view even though the content area is hidden |
| disclosure-card-024 | forces-subtitle-hidden-when-collapsed | Constructed with `subtitle: "note", isCollapsed: true` | The subtitle text is hidden |
| disclosure-card-025 | hides-subtitle-when-absent | Constructed with `subtitle: nil, isCollapsed: false` | The subtitle text is hidden |
| disclosure-card-026 | detaches-empty-body | Constructed with `subtitle: nil, summary: [], isCollapsed: true` | The body section is hidden |
| disclosure-card-027 | matches-bottom-inset-to-empty-body | Same construction as disclosure-card-026 | The card's bottom constraint constant equals `-padTitleY`, not `-padY` |
| disclosure-card-028 | shows-summary-only-when-collapsed-and-present | Four combinations of `isCollapsed` × `summary.isEmpty` | The summary line is shown only for `(isCollapsed: true, summary: non-empty)`; hidden for the other three combinations |
| disclosure-card-029 | right-aligns-and-clips-summary-text | Any instance | The summary line's alignment `== right`; it clips rather than truncates when the reserved width is exceeded; it holds its natural width |
| disclosure-card-030 | formats-summary-parts | `summary: [SummaryPart(name: "5H", value: "23%", colorName: "red")]` | The summary line's rendered text contains `"5H: "` in caption font/`tertiaryTextColor` followed by `"23%"` in code font/`dangerColor` (via the name→role color lookup, see below) |
| disclosure-card-031 | separates-summary-parts | `summary` with two `SummaryPart`s | The summary line's rendered text contains exactly one `"  |  "` run, positioned between the two parts, styled like a summary name |
| disclosure-card-032 | hides-status-badge-when-absent | Constructed with `status: nil` | The status badge is hidden |
| disclosure-card-033 | renders-status-as-symbol-icon | Constructed with `status: StatusSymbol(symbolName: "exclamationmark.triangle.fill", colorName: "yellow", accessibilityLabel: "Warning")` | The status badge's image is a valid symbol icon named `"exclamationmark.triangle.fill"`; its weight is semibold |
| disclosure-card-034 | exposes-status-as-own-accessibility-element | Same construction as disclosure-card-033 | The status badge is its own accessibility element; its role is image; its accessibility label `== "Warning"`; its tooltip `== "Warning"` |
| disclosure-card-035 | colors-status-badge | `status.colorName: nil` vs. `"blue"` | The status badge's tint `== palette.secondaryTextColor` when `nil`; `== palette.accentColor` when `"blue"` (per the name→role color lookup, see below) |
| disclosure-card-036 | positions-badge-on-visible-corner | Any instance with a non-nil `status` | The status badge's center-X `==` the card's trailing edge minus `cornerPeakInset`; its center-Y `==` the card's top edge plus `cornerPeakInset`, where `cornerPeakInset ≈ 2.93` |
| disclosure-card-037 | sizes-badge-diameter | `scaledSize == 13` | The status badge's width and height both equal `min(ceil(13 × 1.3), padX × 1.5)`, with `padX` evaluated at `scaledSize == 13` |
| disclosure-card-038 | dims-whole-card-uniformly | Constructed with `isDimmed: true` vs. `false` | `view.opacity == 0.55` when `true`; `== 1.0` when `false` |
| disclosure-card-039 | scales-insets-with-text-size | `scaledSize == 26` (2× the 13pt baseline), assuming `baseFontSize == 13` on the host system | `padX == ceil(14 × 26 / 13) == 28`; `padMastheadX == ceil(7 × 26 / 13) == 14`; `padY == ceil(12 × 26 / 13) == 24`; `padTitleY == ceil(6 × 26 / 13) == 12`; `mastheadGap == ceil(24 × 26 / 13) == 48` |
| disclosure-card-040 | floors-width-to-wider-of-open-or-folded-content | Card with a wide content area and a non-empty `summary`, both open and folded | The width-floor constraint's constant is identical whether `isCollapsed` is `true` or `false`, and equals the wider of the two rows plus the masthead's leading gutter (`padMastheadX`) and trailing gutter (`padX`) |
| disclosure-card-041 | keeps-width-floor-just-under-required | Any instance | The width-floor constraint's priority equals 999 |
| disclosure-card-042 | remeasures-width-floor-on-layout | Font/theme change that widens the hidden content area after initial layout, followed by a layout pass | The width-floor constraint's constant updates to the new wider value; a follow-up layout pass with no further change does not reassign the constant (change is `<= 0.5pt`) |
| disclosure-card-043 | applies-theme-immediately-and-on-change | Construct a card, then trigger a theme change | The theme is applied once synchronously at construction and again after the theme change, updating colors/fonts both times |
| disclosure-card-046 | exposes-content-spacing | Set the content spacing to 20 | The content area's spacing `== 20`; the width-floor constraint is re-measured against the new spacing |
| disclosure-card-047 | places-title-status-after-title | Constructed with `titleTrailingStatus: StatusSymbol(symbolName: "checkmark.seal.fill", colorName: "green", accessibilityLabel: "Best")` | The title row holds an image element after the title text; its leading edge is at or after the title's trailing edge and less than 12pt from it |
| disclosure-card-048 | exposes-title-status-like-badge, colors-status-badge | `titleTrailingStatus: StatusSymbol(symbolName: "xmark.seal.fill", accessibilityLabel: "Out of quota", color: { _ in purple })` | The symbol's opacity `== 1`; it is its own accessibility element; its accessibility label `== "Out of quota"`; its tooltip `== "Out of quota"`; its tint `== purple` |
| disclosure-card-049 | reserves-placeholder-room-silently | Two cards with a long title and 40pt content, one given the seal of vector 047 and one `.placeholder(sizedLike: "checkmark.seal.fill")` | Both cards' fitting widths are equal (±0.5); the placeholder is as wide as the seal; it is not hidden, its opacity `== 0`, it is no accessibility element, and it has no tooltip |
| disclosure-card-050 | asks-for-whole-point-title-width, floors-width-to-wider-of-open-or-folded-content | A card with a long title, no `summary`, and 40pt content, hosted at exactly its own fitting width | The title text's laid-out width is at least its own fitting width − 0.5 — it is not truncated |

The name→role color lookup (`"red"` → `dangerColor`, `"blue"` →
`accentColor`, and so on) is defined outside this specification — see Platform Notes.

## Edge Cases

- **Empty `title`** (`""`): Documented limitation — `displays-title-text`
  requires the exact `title` string to be displayed, and the source performs
  no empty-string check: the title text renders an empty string and the
  header row lays out with a zero-width title.
- **Very long `title` with no accessories**: truncated in the middle rather
  than the tail or head (MUST, per `truncates-title-in-middle`); the
  required minimum header gap and the trailing line's required compression
  resistance keep the disclosure control fully visible regardless of title
  length (MUST, per `maintains-minimum-header-gap` and
  `never-shrinks-trailing-line`).
- **`summary` non-empty while `isCollapsed == false` at construction**: the
  summary row itself stays hidden (per `shows-summary-only-when-collapsed-
  and-present`), but the masthead width floor (see Appearance) is still
  computed from `summary` whenever the theme is applied, regardless of
  `isCollapsed`, so an initially-open card's width floor already reserves
  room for the summary line it would show if folded (MUST, per
  `floors-width-to-wider-of-open-or-folded-content`).
- **`summary` empty and `isCollapsed == true`**: the card renders as
  exactly its titlebar, with the body section fully detached and the
  bottom inset switched to `padTitleY` (MUST, per `detaches-empty-body`
  and `matches-bottom-inset-to-empty-body`).
- **A `StatusSymbol.symbolName` does not resolve to a valid symbol icon**:
  Documented limitation — `renders-status-as-symbol-icon` and
  `places-title-status-after-title` require a symbol icon, and the source
  performs no validation of `symbolName`: the symbol lookup substitutes a
  blank 16×16 image, so the badge (or the symbol after the title) keeps its
  frame, position, and accessibility label/tooltip, but no glyph paints. A
  placeholder sized like an unresolved name holds that blank image's 16pt
  of room.
- **Extreme `scaledSize` values** (very small, e.g. approaching 0, or very
  large, e.g. an accessibility "larger text" size well above the 13pt
  baseline): every inset and font scales linearly and is rounded up, with
  no minimum clamp — an extremely small `scaledSize` can drive insets
  toward 0pt. The status badge diameter is the one value with an explicit
  upper bound (`min(ceil(scaledSize × 1.3), padX × 1.5)`, with `padX`
  evaluated at that `scaledSize` — see Appearance); every other scaled
  constant is otherwise unbounded above (MUST, per
  `scales-insets-with-text-size` and `sizes-badge-diameter`).
- **Concurrent access**: Not applicable — this component is confined to a
  single thread of execution for its entire lifetime, so there is no
  concurrent-access surface for it to define behavior for. See Platform Notes for how that confinement is enforced.
- **Error states (dependency/network failure)**: Not applicable — the
  source performs no network call, database access, or file-system I/O of
  any kind.
- **Offline/disconnected state**: Not applicable — the component has no
  networking dependency of its own.
- **Boundary values**: `cornerRadius`, `borderWidth`, `horizontalInset`,
  `verticalInset`, `titlebarInset`, `mastheadInset`,
  `mastheadGapAtSystemSize`, `iconGap`, and `dimmedAlpha` are fixed
  literals, not caller-configurable ranges with a boundary to test (the gap
  itself scales with `scaledSize`, per `scales-insets-with-text-size`). `scaledSize` is the one
  caller-configurable numeric input; its boundary behavior is covered
  above under "Extreme `scaledSize` values."

## Configuration

Construction options:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `title` | `String` | — (required) | Text shown in the titlebar |
| `titleIsAccent` | `Bool` | — (required) | Colors `title` with `accentColor` when `true`, `primaryTextColor` when `false` |
| `titleAccessory` | `View?` | `nil` | View placed before the title, e.g. a host's logo mark |
| `titleTrailingStatus` | `StatusSymbol?` | `nil` | Symbol drawn right after the title, at the title's size, e.g. a seal on the one card in a stack worth acting on; a stack that marks only some cards hands the rest `StatusSymbol.placeholder(sizedLike:)` so every card asks for the same width |
| `titlebarAccessory` | `View?` | `nil` | View placed before the disclosure control, e.g. a per-card menu |
| `subtitle` | `String?` | `nil` | One quiet line under the masthead; hidden whenever the card is collapsed |
| `summary` | `[SummaryPart]` | `[]` | Readings shown on their own right-aligned line only while the card is collapsed |
| `status` | `StatusSymbol?` | `nil` | Symbol stamped on the card's top-right corner |
| `isCollapsed` | `Bool` | `false` | Whether the card is constructed folded; fixed for the instance's lifetime |
| `isDimmed` | `Bool` | `false` | Whether the whole card renders at reduced (0.55) opacity |
| `scaledSize` | `CGFloat` | — (required) | The text size driving every scaled inset, font, and badge dimension |
| `onToggle` | `((Bool) -> Void)?` | `nil` | Called with the requested new collapsed state when the disclosure control is activated |

`SummaryPart`:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `name` | `String` | — (required) | The reading's label, e.g. `"5H"` |
| `value` | `String` | — (required) | The reading's value, e.g. `"23%"` |
| `color` | `(SemanticPalette) -> Color?` | — (required, or derived from `colorName`) | Resolves the value's color against the live palette each time it is called |
| `colorName` (convenience option) | `String?` | — | Looked up via `palette.color(named:)` in place of a custom `color` closure |

Callers SHOULD supply `color` as a closure that resolves against the live
`SemanticPalette` each time it is called (or use the `colorName` convenience
option, which does this automatically), rather than capturing a static color
at construction time — a captured static color will not update on a theme
change. This is caller-side guidance: the component has no way to enforce it
and no observable behavior distinguishes a dynamic `color` closure from a
static one, so it has no requirement or test vector of its own.

`StatusSymbol`:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `symbolName` | `String` | — (required) | Symbol name rendered in the corner badge or after the title |
| `color` | `(SemanticPalette) -> Color?` | — (required, or derived from `colorName`) | Resolves the symbol's tint against the live palette on every theme application; `nil` falls back to `secondaryTextColor` |
| `colorName` (convenience option) | `String?` | — | Looked up via `palette.color(named:)` in place of a custom `color` closure |
| `accessibilityLabel` | `String` | — (required) | Used as both the symbol's accessibility label and its tooltip |
| `isPlaceholder` | `Bool` | `false` (read-only) | `true` only for `StatusSymbol.placeholder(sizedLike:)`, which holds the named symbol's room with nothing drawn, spoken, or explained |

Beyond construction, the component exposes: an operation to add a content
view to the content area; a read/write property controlling the content
area's spacing (`contentSpacing`); and a read-only property exposing whether
the card is currently collapsed (`isCollapsed`).

## Deep Linking

Not applicable: this is a display/layout component with no route, URL
scheme handling, or navigable identity of its own.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded literal) | `Show details` | Disclosure control's tooltip and accessibility label when constructed `isCollapsed: true` |
| (none — hardcoded literal) | `Hide details` | Disclosure control's tooltip and accessibility label when constructed `isCollapsed: false` |

`title`, `subtitle`, `summary`'s `name`/`value` strings,
`status.accessibilityLabel`, and `titleTrailingStatus.accessibilityLabel`
are all caller-supplied at the call site — the
component defines no string literals of its own for them. The two disclosure
strings above ARE component-owned literals, and the source assigns them
directly (`"Show details"`/`"Hide details"`) with no localization key or
string-catalog entry — a real localization gap for a component intended to
ship in a localized app, documented here rather than smoothed over.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the component performs no animation or transition anywhere — every state change (theme colors, fonts, the width floor) is an instantaneous property or constraint-constant assignment. |
| Increase Contrast | Not applicable to this component directly: the source reads no system contrast setting; every color it draws comes from the active `SemanticPalette`, and whether the resulting contrast is sufficient is tracked once under Accessibility above, not duplicated here. |
| Differentiate Without Color | Satisfied: the disclosure state is communicated by the control's own orientation plus its tooltip/label text, not color; the status badge and the title status symbol each pair their tint with a symbol icon shape and an `accessibilityLabel`; and every summary value is always paired with its `name` text label (`formats-summary-parts`) rather than color alone. |

## Feature Flags

Not applicable: the source contains no feature-flag reads. The card renders
unconditionally whenever it is constructed.

## Analytics

Not applicable: the source contains no analytics, tracking, or telemetry
call.

## Privacy

- **Data collected**: None — the component holds only the `title`,
  `subtitle`, `summary`, `status`, `titleTrailingStatus`, and accessory
  values passed to it by the caller; it originates no data of its own.
- **Storage**: Not applicable — the component performs no persistence of
  any kind. (A companion fold-memory helper persists which cards are
  folded, but that is a separate file the host wires in; it is not part of
  this source.)
- **Transmission**: Not applicable — the source performs no network I/O.
- **Retention**: Not applicable — the view retains only its own subviews
  and the caller-supplied values for its own instance lifetime.

## Logging

Not applicable: the source contains no logging call.

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
- **AppKit / UIKit** (source platform): The component (`DisclosureCardView`)
  is declared `@MainActor` and is an `NSView` subclass conforming to
  `Themeable`; it fails to compile if constructed or mutated from off the
  main actor, and it is unavailable via `init?(coder:)` — attempting to
  construct it from a storyboard/nib (`init?(coder:)`, declared
  `@available(*, unavailable)`) traps with a fatal error rather than
  returning a usable instance. Source at
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

  API and literal mappings: the disclosure control is an `NSButton` with
  `bezelStyle = .disclosure` and `buttonType = .onOff`; its two states are
  `.off` (closed/collapsed indicator) and `.on` (open/expanded indicator).
  The card sets `clipsToBounds = false` on itself so the status badge can
  render outside its frame, and adds the badge as a sibling subview after
  the card surface — a `CALayer` otherwise draws a layer's own border
  above all of that layer's sublayers, so the badge must live outside the
  surface's layer tree to paint above its border. `dims-whole-card-
  uniformly` sets the whole view's `alphaValue`, not a substitute color
  set. The title text's line-break mode is `.byTruncatingMiddle`; the
  summary line's is `.byClipping`. Title/trailing-row shrink priority is
  expressed as Auto Layout compression-resistance/content-hugging
  priorities: `.defaultLow` for the title and its row, `.required` for the
  trailing row and other elements that must not shrink; the width-floor
  constraint's own priority is `999` (just under `.required`). Every
  scaled inset (`padX`, `padMastheadX`, `padY`, `padTitleY`, `mastheadGap`)
  is computed as
  `ceil(constant × scaledSize / NSFont.systemFontSize)` —
  `NSFont.systemFontSize` is the literal source of this recipe's "base
  system font size" (`baseFontSize`). The status badge renders `status` via
  `NSImage.symbol(named: status.symbolName, accessibilityDescription:
  status.accessibilityLabel)` (AgenticToolkitCoreUI's never-nil SF Symbol
  lookup, which substitutes a blank 16×16 template image for an unknown
  name) at a `.semibold` symbol configuration, and the title status symbol
  the same way at a point size of `scaledSize`; a placeholder is drawn at
  `alphaValue == 0`, never `isHidden`, since an `NSStackView` gives a
  hidden arranged view no room. The status badge's and title status
  symbol's accessibility role is set to `.image`. The whole-point title
  width comes from `WholePointLabel`, AgenticToolkitCoreUI's `NSTextField`
  subclass (`CoreUI/WholePointLabel.swift`) that rounds its
  `intrinsicContentSize` width up with `ceil`.
  The card draws no shadow: it sets no `shadowColor`, `shadowRadius`, or
  `shadowOpacity` on any `CALayer`. The source performs no
  `NSAnimationContext`/`CATransaction`-driven animation. Theme application
  happens via a `ThemePaletteObserver` held for the view's lifetime.
  `applyTheme(_:)` is the source's own theme-application entry point,
  invoked once at construction and again on every theme change; it is also
  what recomputes the masthead width floor from `summary` regardless of
  the card's `isCollapsed` value at construction.

  The recipe's descriptive terms above map to these source private members:
  the card surface is `surface`; the titlebar strip is `titlebar`; the
  titlebar's bottom rule is `titlebarRule`; the title text is `titleField`
  (a `WholePointLabel`); the title status symbol is `titleStatusIcon`; the
  title row is `titleLine`; the trailing row is `trailingLine`; the
  disclosure control is `disclosure`; the content area is `content`; the
  body section is `body`; the subtitle text is `subtitleField`; the summary
  line is `summaryField`; the status badge is `statusIcon`; and the
  width-floor constraint is `contentWidthFloor`. `color(named:)`'s
  name→role map (`"red"` → `dangerColor`, `"blue"` → `accentColor`, and so
  on) is defined outside this source, in
  `external/agenticdevelopertoolkit/packages/apple/AgenticDeveloperToolkit/SourcesUI/macOS/Theme/SemanticPalette+NSColor.swift`.

  Public API surface (beyond construction):
  ```swift
  public func addContent(_ view: NSView)
  public var contentSpacing: CGFloat { get set }
  public var isCollapsed: Bool { get }
  ```
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/Cards/DisclosureCardView.swift` |

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
  **Approved**: pending
- **Decision**: The width floor is computed as the wider of the open
  content's fitting width and the folded masthead's width, and is
  recomputed on every `layout()` pass regardless of the card's current
  fold state.
  **Rationale**: Per the type's own doc comment, "a card is exactly as wide
  folded as it is open" — a content-hugging window that re-derived its
  width from whichever state happened to be visible would jump sideways on
  every fold, which is what this fold-independent floor prevents.
  **Approved**: pending
- **Decision**: The status badge is centered on `cornerPeakInset`
  (`cornerRadius − cornerRadius/√2`), not on the frame's literal corner,
  and is added as a top-level sibling subview after `surface` rather than
  inside it.
  **Rationale**: Per the type's own doc comment, a rounded card has no ink
  at the square corner, so centering there would look like the badge
  "slipped off"; and a `CALayer` draws its own border above its sublayers,
  so the badge must live outside `surface`'s layer tree to paint above that
  border.
  **Approved**: pending
- **Decision**: Dimming is a single `alphaValue` applied to the whole view,
  not a second set of dimmed theme colors.
  **Rationale**: Per the type's own doc comment, this makes the card
  recede "complete — border, surface, content and all" while every color
  it draws keeps meaning exactly what it means on the live card.
  **Approved**: pending
- **Decision**: `titleAccessory` and `titlebarAccessory` are placed and
  measured but never styled, tinted, or given any accessibility
  configuration by the component.
  **Rationale**: Per the type's own doc comment, a host that passes a view
  has already decided its appearance and behavior; recoloring or otherwise
  opinionating on it would fight a caller that, for example, hands in a
  logo that is also a button.
  **Approved**: pending
- **Decision**: The symbol after the title is described by a `StatusSymbol`
  value, not handed in as a view, and `StatusSymbol.placeholder(sizedLike:)`
  holds the named symbol's room with nothing drawn, spoken, or explained.
  **Rationale**: Unlike `titleAccessory`, this mark is the card's own
  vocabulary: it must be sized to the title, tinted from the live palette
  on every theme change, and spoken exactly like the corner badge, so the
  card owns its rendering rather than trusting each host to repeat it. The
  placeholder exists because a stack of cards that marks only one of them
  would otherwise make that card — and so a content-hugging window — jump a
  symbol's width wider whenever the mark moved to another card or went
  away; handing every unmarked card the placeholder keeps each card's
  requested width independent of which card is marked.
  **Approved**: pending
- **Decision**: The masthead width floor (`asks-for-whole-point-title-width`
  and the title-plus-gap floor) applies to every card, with or without a
  summary.
  **Rationale**: A card with no summary still has a title that the
  content-hugging window must fit whole; limiting the floor to summarized
  cards let a long title truncate in the one card with nothing else to
  widen it.
  **Approved**: pending
- **Decision**: The disclosure control's tooltip/accessibility label
  strings (`"Show details"`, `"Hide details"`) are English literals with no
  localization key.
  **Rationale**: Documented here rather than idealized away — the source
  has no string-catalog or localization call for these two strings, unlike
  every other piece of text on the card, which is entirely caller-supplied.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Platform Compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | Platform Compliance |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`keyboard-navigable`, `native-controls-preference`, and
`platform-design-language` rest on what the source visibly does (the native
`NSButton`/`NSStackView` controls); `screen-reader-support` and `contrast-ratio`
are `partial` because the source cannot settle, respectively, the disclosure
label's staleness between a click and the host's rebuild (see
`does-not-self-mutate-on-toggle`) and each shipped theme's actual resolved
contrast ratios; `no-hardcoded-strings` is `failed` because
`"Show details"`/`"Hide details"` are English literals with no
localization key (see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial recipe — extracted from the Apple `DisclosureCardView` (AppKit, macOS) source. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: shortened the frontmatter summary and moved the platform-design-languages reference from `references` to `related`; restated Behavioral Requirements, States, Edge Cases, and Conformance Test Vectors in observable terms instead of private Swift member names, with the member-name mapping relocated to AppKit Platform Notes; defined `cornerPeakInset`, badge diameter, and the masthead width floor in Appearance; documented the `color(named:)` name-to-role map; added a precondition to vector 039; moved `prefers-dynamic-summary-colors` into a Configuration usage note; reworded the two no-guard Edge Cases as documented limitations; fixed the UIKit, React/Web, WinUI 3, and Compose Platform Notes bullets; reformatted Design Decisions' `Approved` line; and updated Compliance (`contrast-ratio` and `screen-reader-support` to `partial`, added a failing `no-hardcoded-strings` row, Title Case categories, and a rationale sentence).; removed Compliance rows for checks absent from the cookbook catalog |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-26 | Mike Fullerton | Documented the title status symbol: `titleTrailingStatus` (a `StatusSymbol` drawn right after the title at its size), `StatusSymbol.placeholder(sizedLike:)` and its silent reserved room, the palette-resolving `color` closure with the `colorName` convenience init, the CoreUI `WholePointLabel` title, the text-size-scaled masthead gap, and the width floor for every card; added requirements, vectors 047–050, configuration rows, edge cases, and two design decisions. |
| 1.3.0 | 2026-10-01 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/containers/. |
