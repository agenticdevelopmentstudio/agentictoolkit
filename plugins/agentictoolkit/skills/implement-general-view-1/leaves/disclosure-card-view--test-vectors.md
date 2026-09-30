<!-- leaf: implement-general-view-1/disclosure-card-view--test-vectors · source: disclosure-card-view.md -->

# DisclosureCardView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| disclosure-card-001 | renders-card-as-rounded-bordered-surface | Any `init(...)` call | The card surface's layer has `cornerRadius == 10`, `borderWidth == 1`, `backgroundColor == palette.surfaceColor.cgColor`, and `borderColor == palette.outlineColor.cgColor` |
| disclosure-card-002 | clips-titlebar-to-card-corners | Any `init(...)` call | The card surface's layer has `masksToBounds == true` |
| disclosure-card-003 | renders-titlebar-as-elevated-strip | Any `init(...)` call | The titlebar strip's layer `backgroundColor == palette.elevatedSurfaceColor.cgColor` |
| disclosure-card-004 | draws-titlebar-rule | Any `init(...)` call | The titlebar's bottom rule's layer `backgroundColor == palette.dividerColor.cgColor`; its height constraint equals 1pt and it spans the titlebar's width |
| disclosure-card-005 | sizes-titlebar-to-header-plus-inset | Card at a given `scaledSize` | The titlebar strip's height equals the header row's fitting height plus `padTitleY` |
| disclosure-card-006 | draws-badge-above-surface-border | Card constructed with a non-nil `status` | The status badge appears later in the card's `subviews` than the card surface, and renders visually above the surface's border in a snapshot |
| disclosure-card-007 | allows-badge-to-render-outside-frame | Any `init(...)` call | `clipsToBounds == false` on the card |
| disclosure-card-008 | displays-title-text | `init(title: "mike@example.com", ...)` | The title text's `stringValue == "mike@example.com"` |
| disclosure-card-009 | truncates-title-in-middle | The title text's line-break mode, inspected on any instance | Equals `.byTruncatingMiddle` |
| disclosure-card-010 | yields-title-width-first | Any instance | The title text and title row's compression-resistance and hugging priorities (horizontal) equal `.defaultLow`, lower than the trailing row's `.required` |
| disclosure-card-011 | colors-title-by-accent-flag | `init(..., titleIsAccent: true, ...)` vs. `false` | The title text's color `== palette.accentColor` when `true`; `== palette.primaryTextColor` when `false` |
| disclosure-card-012 | sets-title-font-semibold-body | Theme applied at a given `scaledSize` | The title text's font matches `.body` style at `scaledSize` with `.semibold` weight |
| disclosure-card-013 | places-title-accessory-leading | `init(..., titleAccessory: someView, ...)` | The title row's arranged subviews equal `[someView, <title text>]`; spacing `== 6`; `someView`'s horizontal compression resistance is `.required` |
| disclosure-card-014 | places-titlebar-accessory-before-disclosure | `init(..., titlebarAccessory: someView, ...)` | The trailing row's arranged subviews equal `[someView, <disclosure control>]`; spacing `== 6` |
| disclosure-card-015 | never-shrinks-trailing-line | Any instance | The trailing row's horizontal compression-resistance and hugging priorities both equal `.required` |
| disclosure-card-016 | maintains-minimum-header-gap | Card at `scaledSize == 16` narrowed until the title and trailing rows compete for space, assuming `NSFont.systemFontSize == 13` | The gap between the title row's trailing edge and the trailing row's leading edge is never less than `ceil(24 × 16 / 13) == 30`pt; the two rows share a common center-Y (per `testAStackOfCardsIsAsWideAsItsLongestTitle`) |
| disclosure-card-017 | renders-native-disclosure-control | Any instance | The disclosure control is an `NSButton` with `bezelStyle == .disclosure` and `buttonType == .onOff` |
| disclosure-card-018 | sets-disclosure-initial-state | `init(..., isCollapsed: true, ...)` vs. `false` | The disclosure control's `state == .off` when `true`; `== .on` when `false` |
| disclosure-card-019 | labels-disclosure-control | `init(..., isCollapsed: true, ...)` vs. `false` | The disclosure control's `toolTip` and accessibility label equal `"Show details"` when `true`; `"Hide details"` when `false` |
| disclosure-card-020 | forwards-toggle-state | Click the disclosure control on a card constructed `isCollapsed: false` | `onToggle` is called once with `true` (the control's new state is `.off`) |
| disclosure-card-021 | does-not-self-mutate-on-toggle | Click the disclosure control on any card, inspect the same instance immediately after | The content area's visibility, the body section's visibility, the subtitle text's visibility, and the disclosure control's `toolTip` are all unchanged from their pre-click values |
| disclosure-card-022 | hides-content-when-collapsed | `init(..., isCollapsed: true, ...)` vs. `false` | The content area is hidden when `true`; shown when `false` |
| disclosure-card-023 | builds-content-regardless-of-fold-state | `addContent(someView)` on a card constructed `isCollapsed: true` | The content area's arranged subviews include `someView` even though the content area is hidden |
| disclosure-card-024 | forces-subtitle-hidden-when-collapsed | `init(..., subtitle: "note", isCollapsed: true, ...)` | The subtitle text is hidden |
| disclosure-card-025 | hides-subtitle-when-absent | `init(..., subtitle: nil, isCollapsed: false, ...)` | The subtitle text is hidden |
| disclosure-card-026 | detaches-empty-body | `init(..., subtitle: nil, summary: [], isCollapsed: true, ...)` | The body section is hidden |
| disclosure-card-027 | matches-bottom-inset-to-empty-body | Same construction as disclosure-card-026 | The card's bottom constraint constant equals `-padTitleY`, not `-padY` |
| disclosure-card-028 | shows-summary-only-when-collapsed-and-present | Four combinations of `isCollapsed` × `summary.isEmpty` | The summary line is shown only for `(isCollapsed: true, summary: non-empty)`; hidden for the other three combinations |
| disclosure-card-029 | right-aligns-and-clips-summary-text | Any instance | The summary line's alignment `== .right`; line-break mode `== .byClipping`; horizontal compression resistance `.required` |
| disclosure-card-030 | formats-summary-parts | `summary: [SummaryPart(name: "5H", value: "23%", colorName: "red")]` | The summary line's rendered text contains `"5H: "` in caption font/`tertiaryTextColor` followed by `"23%"` in code font/`dangerColor` (via `color(named: "red")`, see below) |
| disclosure-card-031 | separates-summary-parts | `summary` with two `SummaryPart`s | The summary line's rendered text contains exactly one `"  |  "` run, positioned between the two parts, styled like a summary name |
| disclosure-card-032 | hides-status-badge-when-absent | `init(..., status: nil, ...)` | The status badge is hidden |
| disclosure-card-033 | renders-status-as-sf-symbol | `init(..., status: StatusSymbol(symbolName: "exclamationmark.triangle.fill", colorName: "yellow", accessibilityLabel: "Warning"), ...)` | The status badge's image is a valid SF Symbol image named `"exclamationmark.triangle.fill"`; its symbol configuration weight `== .semibold` |
| disclosure-card-034 | exposes-status-as-own-accessibility-element | Same construction as disclosure-card-033 | The status badge is its own accessibility element (`isAccessibilityElement() == true`); `accessibilityRole() == .image`; `accessibilityLabel() == "Warning"`; `toolTip == "Warning"` |
| disclosure-card-035 | colors-status-badge | `status.colorName: nil` vs. `"blue"` | The status badge's tint `== palette.secondaryTextColor` when `nil`; `== palette.accentColor` when `"blue"` (per `color(named:)`'s name→role map, see below) |
| disclosure-card-036 | positions-badge-on-visible-corner | Any instance with a non-nil `status` | The status badge's center-X `== trailingAnchor - cornerPeakInset`; its center-Y `== topAnchor + cornerPeakInset`, where `cornerPeakInset ≈ 2.93` |
| disclosure-card-037 | sizes-badge-diameter | `scaledSize == 13` | The status badge's width and height both equal `min(ceil(13 × 1.3), padX × 1.5)`, with `padX` evaluated at `scaledSize == 13` |
| disclosure-card-038 | dims-whole-card-uniformly | `init(..., isDimmed: true, ...)` vs. `false` | `view.alphaValue == 0.55` when `true`; `== 1.0` when `false` |
| disclosure-card-039 | scales-insets-with-text-size | `scaledSize == 26` (2× the 13pt baseline), assuming `NSFont.systemFontSize == 13` on the host system | `padX == ceil(14 × 26 / 13) == 28`; `padMastheadX == ceil(7 × 26 / 13) == 14`; `padY == ceil(12 × 26 / 13) == 24`; `padTitleY == ceil(6 × 26 / 13) == 12`; `mastheadGap == ceil(24 × 26 / 13) == 48` |
| disclosure-card-040 | floors-width-to-wider-of-open-or-folded-content | Card with a wide content area and a non-empty `summary`, both open and folded | The width-floor constraint's constant is identical whether `isCollapsed` is `true` or `false`, and equals the wider of the two rows plus the masthead's leading gutter (`padMastheadX`) and trailing gutter (`padX`) |
| disclosure-card-041 | keeps-width-floor-just-under-required | Any instance | The width-floor constraint's `priority.rawValue == 999` |
| disclosure-card-042 | remeasures-width-floor-on-layout | Font/theme change that widens the hidden content area after initial layout, followed by a layout pass | The width-floor constraint's constant updates to the new wider value; a follow-up layout pass with no further change does not reassign the constant (change is `<= 0.5pt`) |
| disclosure-card-043 | applies-theme-immediately-and-on-change | Construct a card, then trigger a theme change | `applyTheme(_:)` runs once synchronously at construction and again after the theme change, updating colors/fonts both times |
| disclosure-card-044 | rejects-storyboard-instantiation | `DisclosureCardView(coder:)` invoked (e.g. via nib/storyboard unarchiving) | Process traps with a fatal error |
| disclosure-card-045 | confines-mutation-to-main-actor | Attempt to call `DisclosureCardView.init`/`addContent`/`contentSpacing` from a non-main-actor context | Code does not compile (Swift concurrency checker rejects the call) |
| disclosure-card-046 | exposes-content-spacing | `card.contentSpacing = 20` | The content area's stack spacing `== 20`; the width-floor constraint is re-measured against the new spacing |
