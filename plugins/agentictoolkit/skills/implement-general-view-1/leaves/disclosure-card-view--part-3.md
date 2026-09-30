<!-- leaf: implement-general-view-1/disclosure-card-view--part-3 · source: disclosure-card-view.md -->

# DisclosureCardView — continued (part 3)

**Rules** (cite as `implement-general-view-1/disclosure-card-view--part-3#<slug>`):

- `positions-badge-on-visible-corner` MUST
- `sizes-badge-diameter` MUST
- `dims-whole-card-uniformly` MUST
- `scales-insets-with-text-size` MUST
- `floors-width-to-wider-of-open-or-folded-content` MUST
- `keeps-width-floor-just-under-required` MUST
- `remeasures-width-floor-on-layout` MUST
- `applies-theme-immediately-and-on-change` MUST
- `rejects-storyboard-instantiation` MUST
- `confines-mutation-to-main-actor` MUST
- `exposes-content-spacing` MUST

- **positions-badge-on-visible-corner**: Component MUST center the status
  badge, on both axes, `cornerPeakInset` (`cornerRadius − cornerRadius/√2`,
  ≈2.93pt at the fixed 10pt radius) inside the card's top-right corner —
  the point where the rounded corner's arc actually turns — not on the
  frame's literal square corner.
- **sizes-badge-diameter**: Component MUST size the status badge to
  `min(ceil(scaledSize × 1.3), padX × 1.5)` on each axis (see Appearance for
  `padX`).
- **dims-whole-card-uniformly**: Component MUST set the entire view's
  `alphaValue` to 0.55 when constructed with `isDimmed == true`, and to
  `1.0` otherwise, rather than substituting a separate set of dimmed
  colors.
- **scales-insets-with-text-size**: Component MUST scale
  `horizontalInset` (14), `mastheadInset` (7), `verticalInset` (12),
  `titlebarInset` (6), and the masthead gap (`mastheadGapAtSystemSize`, 24)
  linearly by `scaledSize ÷ NSFont.systemFontSize`, rounding each result up
  (`ceil`), rather than using fixed point values.
- **floors-width-to-wider-of-open-or-folded-content**: Component MUST
  constrain its own width to be greater than or equal to the wider of (a)
  the content area's fitting width and (b) the masthead's folded-state
  width (the title-row-plus-trailing-row line, or the summary line,
  whichever is wider) — plus the masthead's leading gutter (`padMastheadX`)
  and trailing gutter (`padX`) — regardless of whether the card is
  currently open or folded, and whether or not it has a `summary`: a card
  with no summary still asks for the room to write its title whole.
- **keeps-width-floor-just-under-required**: Component MUST set the width-
  floor constraint's priority to `999` (just under `.required`), so a
  container too narrow for the content scrolls rather than making the
  layout unsatisfiable.
- **remeasures-width-floor-on-layout**: Component MUST recompute its width
  floor on every layout pass, but MUST only apply the newly computed
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
  property that reads and writes the content area's stack spacing, and MUST
  re-measure the width floor whenever it is set.
## Appearance

- **Corner radius**: 10pt, fixed (`cornerRadius`); unaffected by
  `scaledSize`.
- **Padding**: `padX` = `ceil(14 × scaledSize / NSFont.systemFontSize)`, the
  card's trailing gutter — from the card edge to body/content rows and to
  the summary/subtitle's trailing edge; `padMastheadX` =
  `ceil(7 × scaledSize / NSFont.systemFontSize)`, the masthead's own
  leading gutter — from the card edge to the masthead line's leading edge;
  `padY` = `ceil(12 × scaledSize / NSFont.systemFontSize)` as the card's own
  bottom inset when the body section is present; `padTitleY` =
  `ceil(6 × scaledSize / NSFont.systemFontSize)` as the titlebar's own
  top/bottom inset, and as the card's bottom inset when the body section is
  hidden; `iconGap` = 6pt fixed between an accessory or the title status
  symbol and the text/control beside it; `mastheadGap` =
  `ceil(24 × scaledSize / NSFont.systemFontSize)` minimum between the title
  row and the trailing row. The masthead's own width floor (below) reserves
  `padMastheadX` on its leading side and `padX` on its trailing side — the
  same two gutters the card itself is pinned at.
- **Corner peak inset**: `cornerPeakInset` = `cornerRadius − cornerRadius/√2`
  (≈2.93pt at the fixed 10pt `cornerRadius`) — the distance in from the
  frame's literal corner, on both axes, to the point where the rounded
  corner's arc actually turns; what the status badge is centered on.
- **Badge diameter**: `min(ceil(scaledSize × 1.3), padX × 1.5)` — the status
  badge's width and height at a given `scaledSize`.
- **Title status symbol**: drawn at a point size of `scaledSize`, `.semibold`
  weight — the title's own size, since it reads as part of the name — at
  its intrinsic size, with no fixed frame of its own.
- **Masthead width floor**: for every card, the wider of (a) the title
  row's fitting width (leading accessory, whole-point title width, and
  title status symbol or placeholder included) plus `mastheadGap` plus the
  trailing row's fitting width, and (b) the summary line's rendered text
  width when `summary` is non-empty, `0` when it is empty. Feeds
  `floors-width-to-wider-of-open-or-folded-content`.
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
  control tint — `secondaryTextColor`; status badge tint —
  `status.color(palette)`, and title status symbol tint —
  `titleTrailingStatus.color(palette)`, each falling back to
  `secondaryTextColor`.
- **Border**: card surface — 1pt, palette `outlineColor`; titlebar rule —
  1pt, palette `dividerColor` (a filled strip along the titlebar's bottom
  edge, not a stroked `CALayer` border).
- **Shadow**: none — the source sets no `shadowColor`, `shadowRadius`, or
  `shadowOpacity` on any layer.
- **Min/Max size**: none declared as fixed constants. The card's only size
  constraint is the dynamic width-floor constraint (priority 999) described
  above; no explicit minimum or maximum height, and no upper bound on
  width.

## Accessibility

- **Role/trait**: The card itself (`DisclosureCardView`, an `NSView`) sets
  no accessibility role override — it is a plain container. The disclosure
  control is a standard `NSButton` with `bezelStyle = .disclosure`, which
  AppKit exposes with its own native disclosure-triangle accessibility
  role and behavior. `statusIcon` is explicitly given role `.image`
  (`exposes-status-as-own-accessibility-element`), and so is
  `titleStatusIcon` unless it holds a placeholder, which is no
  accessibility element at all (`exposes-title-status-like-badge`,
  `reserves-placeholder-room-silently`). `titleField` is a
  `WholePointLabel` — AgenticToolkitCoreUI's `NSTextField` subclass that
  rounds its intrinsic width up to a whole point
  (`asks-for-whole-point-title-width`) — built with `labelWithString:`;
  `subtitleField` and `summaryField` are plain
  `NSTextField(labelWithString:)` instances. None of the three has a role
  override, so AppKit's default static-text exposure applies to each.
- **Label requirements**: The disclosure control's accessibility label is
  set to `"Show details"`/`"Hide details"` at construction
  (`labels-disclosure-control`). `statusIcon`'s accessibility label is
  `status.accessibilityLabel`, doubling as its tooltip, and
  `titleStatusIcon`'s is `titleTrailingStatus.accessibilityLabel`, likewise
  doubling as its tooltip; a placeholder has neither. `titleField`,
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
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. All colors are drawn from a `SemanticPalette` (`surfaceColor`/`outlineColor`/`primaryTextColor`/etc.), and no numeric contrast check is performed anywhere in `DisclosureCardView.swift`; whether any given theme's title-on-titlebar, subtitle-on-surface, or summary-value-on-surface pairing meets a specific ratio (e.g. WCAG 2.1 AA's 4.5:1) cannot be determined from this file or its palette mapping alone — the actual RGBA values each shipped theme resolves for these roles live outside both, and settling this needs auditing each shipped theme's resolved colors for these role pairings.

