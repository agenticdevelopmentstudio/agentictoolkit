<!-- leaf: implement-general-view-1/disclosure-card-view--part-2 · source: disclosure-card-view.md -->

# DisclosureCardView — continued (part 2)

**Rules** (cite as `implement-general-view-1/disclosure-card-view--part-2#<slug>`):

- `renders-card-as-rounded-bordered-surface` MUST
- `clips-titlebar-to-card-corners` MUST
- `renders-titlebar-as-elevated-strip` MUST
- `draws-titlebar-rule` MUST
- `sizes-titlebar-to-header-plus-inset` MUST
- `draws-badge-above-surface-border` MUST
- `allows-badge-to-render-outside-frame` MUST
- `displays-title-text` MUST
- `truncates-title-in-middle` MUST
- `yields-title-width-first` MUST
- `colors-title-by-accent-flag` MUST
- `sets-title-font-semibold-body` MUST
- `places-title-accessory-leading` MUST
- `places-title-status-after-title` MUST
- `exposes-title-status-like-badge` MUST
- `reserves-placeholder-room-silently` MUST
- `asks-for-whole-point-title-width` MUST
- `places-titlebar-accessory-before-disclosure` MUST
- `never-shrinks-trailing-line` MUST
- `maintains-minimum-header-gap` MUST
- `renders-native-disclosure-control` MUST
- `sets-disclosure-initial-state` MUST
- `labels-disclosure-control` MUST
- `forwards-toggle-state` MUST
- `does-not-self-mutate-on-toggle` MUST
- `hides-content-when-collapsed` MUST
- `builds-content-regardless-of-fold-state` MUST
- `forces-subtitle-hidden-when-collapsed` MUST
- `hides-subtitle-when-absent` MUST
- `detaches-empty-body` MUST
- `matches-bottom-inset-to-empty-body` MUST
- `shows-summary-only-when-collapsed-and-present` MUST
- `right-aligns-and-clips-summary-text` MUST
- `formats-summary-parts` MUST
- `separates-summary-parts` MUST
- `hides-status-badge-when-absent` MUST
- `renders-status-as-sf-symbol` MUST
- `exposes-status-as-own-accessibility-element` MUST
- `colors-status-badge` MUST

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
  surface's own border, which a `CALayer` otherwise draws above all of that
  layer's sublayers.
- **allows-badge-to-render-outside-frame**: Component MUST set
  `clipsToBounds = false` on itself, so the status badge can be drawn
  partially outside the card's own frame.
- **displays-title-text**: Component MUST display the exact `title` string
  passed to `init` as the titlebar's title text.
- **truncates-title-in-middle**: Component MUST truncate the title text in
  the middle (line-break mode `.byTruncatingMiddle`) when it does not fit
  the available width.
- **yields-title-width-first**: Component MUST give the title text and its
  row `.defaultLow` horizontal compression-resistance and content-hugging
  priority, the lowest of any element on the header row, so the title is
  the first thing to shrink when the row is too narrow.
- **colors-title-by-accent-flag**: Component MUST color the title text with
  the palette's `accentColor` when `titleIsAccent == true`, and with
  `primaryTextColor` otherwise.
- **sets-title-font-semibold-body**: Component MUST set the title text's
  font to the palette's `.body` typography style with its `weight`
  overridden to `.semibold`, resolved to a font at `scaledSize`.
- **places-title-accessory-leading**: When `titleAccessory` is non-nil,
  Component MUST place it immediately before the title text inside the
  title row, separated by the icon gap (`iconGap`, 6pt unscaled), and MUST
  give the accessory required horizontal compression resistance so only the
  title text — never the accessory — yields width.
- **places-title-status-after-title**: When `titleTrailingStatus` is
  non-nil, Component MUST draw it immediately after the title text inside
  the title row, separated by the icon gap, as the SF Symbol
  `titleTrailingStatus.symbolName` with a symbol configuration of
  `.semibold` weight at a point size of `scaledSize` (the title's own
  size), and MUST give it required horizontal compression resistance and
  content hugging, so only the title text — never the symbol — yields
  width. Component MUST NOT add anything after the title when
  `titleTrailingStatus` is `nil`.
- **exposes-title-status-like-badge**: For a `titleTrailingStatus` that is
  not a placeholder, Component MUST expose the symbol as its own
  accessibility element with role `.image` and accessibility label
  `titleTrailingStatus.accessibilityLabel`, and MUST set that same string
  as its tooltip.
- **reserves-placeholder-room-silently**: For a `titleTrailingStatus` made
  by `StatusSymbol.placeholder(sizedLike:)`, Component MUST keep exactly
  the room the named symbol would take in the title row — drawn fully
  transparent (`alphaValue == 0`), never hidden, since a stack gives a
  hidden view no room — and MUST NOT expose it as an accessibility element
  or give it a tooltip.
- **asks-for-whole-point-title-width**: Component MUST report the title
  text's intrinsic width rounded up to a whole point (`ceil`), so the width
  the card's floor measures for the title and the width the title is laid
  out at agree, and a title never truncates in a card given exactly its
  own fitting width.
- **places-titlebar-accessory-before-disclosure**: When `titlebarAccessory`
  is non-nil, Component MUST place it immediately before the disclosure
  control inside the trailing row, separated by the icon gap.
- **never-shrinks-trailing-line**: Component MUST give the trailing row (the
  titlebar accessory, if any, plus the disclosure control) required
  horizontal compression-resistance and content-hugging priority, so it
  never yields width to the title row.
- **maintains-minimum-header-gap**: Component MUST keep at least the
  masthead gap (`mastheadGap`, `ceil(24 × scaledSize /
  NSFont.systemFontSize)`, see Appearance) between the title row's trailing
  edge and the trailing row's leading edge, and MUST vertically
  center-align the two rows on the header row.
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
- **does-not-self-mutate-on-toggle**: Component MUST NOT change the content
  area's visibility, the body section's visibility, subtitle visibility, or
  the disclosure control's own `toolTip`/accessibility label as a direct
  result of a disclosure click — a click only invokes `onToggle`. Folding
  is applied only by the host reconstructing the view with a new
  `isCollapsed` (see Design Decisions).
- **hides-content-when-collapsed**: Component MUST hide the content area for
  the lifetime of an instance constructed with `isCollapsed == true`, and
  show it for one constructed with `isCollapsed == false`.
- **builds-content-regardless-of-fold-state**: Component MUST add every
  view passed to `addContent(_:)` to the content area regardless of the
  card's current fold state, so a folded card's content remains measurable.
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
  summary line's text, give it required horizontal compression resistance,
  and clip rather than truncate-with-ellipsis (line-break mode
  `.byClipping`) if the reserved width is ever exceeded.
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
- **renders-status-as-sf-symbol**: Component MUST render a non-nil `status`
  as `NSImage.symbol(named: status.symbolName, accessibilityDescription:
  status.accessibilityLabel)` (AgenticToolkitCoreUI's never-nil symbol
  lookup), with a symbol configuration of `.semibold` weight at a point
  size equal to the status badge's diameter for the current `scaledSize`
  (see `sizes-badge-diameter`).
- **exposes-status-as-own-accessibility-element**: Component MUST expose
  the status badge as its own accessibility element with role `.image` and
  accessibility label `status.accessibilityLabel`, and MUST set that same
  string as its tooltip.
- **colors-status-badge**: Component MUST tint the status badge with
  `status.color(palette)` and the title status symbol with
  `titleTrailingStatus.color(palette)`, each asked of the live palette on
  every theme application and each falling back to `secondaryTextColor`
  whenever it returns `nil` (including when the `StatusSymbol` itself is
  `nil`, or was built with a `nil` `colorName`).
