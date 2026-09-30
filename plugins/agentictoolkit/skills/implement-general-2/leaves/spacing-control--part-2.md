<!-- leaf: implement-general-2/spacing-control--part-2 · source: spacing-control.md -->

# SpacingControl — continued (part 2)

## Appearance

- **Corner radius**: None. The outer frame and every pane are drawn as plain
  rectangles (`NSBezierPath(rect:)`); no rounded-rect path or `cornerRadius`
  appears anywhere in source.
- **Padding**: Not a single vertical × horizontal pair — the whole control
  *is* a spacing editor, and its own outer padding is the fixed chrome
  reserved around the diagram for what hangs off it: `Metrics.chrome`
  (`SpacingControlLayout.swift`) = arrow length (`18pt`) + arrow gap (`2pt`)
  + one field group's width/height (`40 + 2 + 13 = 55pt` wide, `21pt` tall),
  i.e. `75×41pt` on each side of the diagram (`diagramInset`). Within that,
  an arrow's box sits `9pt` (half an arrow length, `attachment`) from the
  line it moves, and a divider's two arrow pairs stand `8pt`
  (`pairOffset` = half arrow breadth + half arrow gap) either side of the
  divider's own centre line.
- **Font**: Number fields use the palette's `.code` text style
  (`palette.font(.code)`) via `observeTheme`; the Reset button uses the
  palette's `.body` text style (`palette.font(.body)`). Neither font size is
  a literal in this file — both are theme tokens resolved by
  `SemanticPalette`, out of this file's scope, and both repaint on a theme
  change.
- **Background**: The outer frame is filled with `palette.projectPaneBackdrop`
  (converted via `NSColor(_:)`); each pane (one for `.frame`, four for
  `.paneDividers`) is filled with `palette.nsColor(.windowBackground)`. Both
  are theme tokens, not literal colors.
- **Foreground/Text**: Number field text uses `palette.nsColor(.primaryText)`.
  Arrow glyphs are tinted with `palette.nsColor(.accent)`
  (`contentTintColor`). Neither is a literal color.
- **Border**: The outer frame is stroked `1pt` with `palette.nsColor(.border)`;
  each pane is stroked `1pt` with `NSColor(palette.projectPaneOutline)`. Both
  paths are inset `0.5pt` on each side (`insetBy(dx: 0.5, dy: 0.5)`) so a
  `1pt` stroke draws crisply on a non-Retina-scaled edge.
- **Shadow**: None. No `NSShadow` or layer shadow appears anywhere in
  source.
- **Min/Max size**: Fixed intrinsic size `420×250pt`
  (`controlSize`/`intrinsicContentSize`); minimum size is the larger of two
  floors — three field groups across/down
  (`fieldGroupSize` `55×21pt` × 3, plus chrome), or the diagram's own floor
  for drawing the full range (`minimumDiagramSize`, tied to
  `maximumDisplayedInset` = `40pt` per side, plus chrome). The diagram
  expands to fill `bounds` above the minimum; no maximum is enforced, since
  `diagramRect` is measured from `bounds` on every layout pass.

## Accessibility

- **Role/trait**: The control sets `setAccessibilityElement(true)` and
  `setAccessibilityRole(.group)` on itself, so it is exposed to VoiceOver as
  one group rather than as four or two loose fields, depending on `style`,
  belonging to nothing (see the type-level doc comment). Every field,
  stepper, arrow button, reset button, and drag handle also carries an
  `accessibilityIdentifier` via the shared `accessibilityID(_:)` helper
  (e.g. `spacing.top`, `spacing.edge.top.more`,
  `spacing.gutter.betweenColumns.narrower.handle`) — these are UI-test
  identifiers (`setAccessibilityIdentifier`), not VoiceOver labels.
- **Label requirements**: The four or two number fields
  (`edgeFields`/`gutterFields`, depending on `style`) and their steppers
  carry no `setAccessibilityLabel`/`setAccessibilityTitleUIElement` call
  anywhere in source — only a numeric value and a test identifier — so a
  VoiceOver user landing on one hears its number with no indication of
  which edge or gutter it belongs to. The arrow buttons are not part of
  this gap: each is built from an
  `NSImage(systemSymbolName:accessibilityDescription:)` whose
  `accessibilityDescription` is the same string as its tooltip (e.g. "More
  top space"), which VoiceOver reads as the button's label. This mirrors
  the same control-to-title linkage gap already noted on the sibling
  ingredient `CaptionedSliderView`
  (`agentictoolkit://recipes/captioned-slider-view#accessibility/label-requirements`).
- **Announce state changes (e.g., loading, disabled)**: Not applicable — the
  component has no loading or disabled state (see States) for a change to
  announce.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven `NSView`/`NSControl` composition with no touch input path
  in source; the 44×44pt minimum is iOS/touch guidance, not a macOS
  pointer-interface requirement.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. Every color this file draws for text or a tint comes from a `SemanticPalette` role — field text (`palette.nsColor(.primaryText)`), arrow glyphs (`palette.nsColor(.accent)`), the outer frame's stroke (`palette.nsColor(.border)`) against `palette.projectPaneBackdrop`, and each pane's stroke (`palette.projectPaneOutline`) against `palette.nsColor(.windowBackground)`) — none of which carry a guaranteed contrast floor in `SemanticPalette.derive(_:theme:)` (`.primaryText` returns the theme's raw foreground, `.accent` returns a raw ANSI slot or the raw foreground, and `.border` blends foreground into background at a fixed 0.18 fraction, unlike `.secondaryText`'s `minContrast: 3.0`), and no check anywhere in `SpacingControl.swift` verifies any of those pairs against the 4.5:1 (text) / 3:1 (non-text) floor; settling it needs a theme-level contrast audit of `SemanticPalette`'s roles against real theme values (see also Accessibility Options: Increase Contrast).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `style` | `SpacingDiagram` (`.frame` \| `.paneDividers`) | — (required) | Selects which subset of `Spacing` the control builds fields, steppers, arrows, and handles for, and which diagram it draws: the four edges (`.frame`) or the two gutters (`.paneDividers`). |
| `value` | `Spacing` | `Spacing()` (all zero) | The numbers currently shown. Assigning it redraws the control but does not invoke `onChange`. |
| `range` | `ClosedRange<Int>` | `0...40` | The floor and ceiling every user-driven edit is clamped to; also sets each stepper's `minValue`/`maxValue`. |
| `onChange` | `((Spacing) -> Void)?` | `nil` | Invoked once per user-driven edit that changes `value` (see fires-onchange-only-on-user-edit / skips-redundant-onchange). Not invoked by assigning `value` directly. |
| `SpacingControl.boundToSettings(style:edges:gutters:range:)` | static factory | — | Not a constructor parameter of `SpacingControl` itself, but the documented way every caller in this framework obtains one: builds a control, then attaches a `SpacingSettingsBinding` (a separate file, out of this recipe's scope) that seeds it from, and keeps it synced with, the given `UserSetting<Int>` values. `edges` (for `.frame`) or `gutters` (for `.paneDividers`) needs to be non-empty for the matching style; `SpacingSettingsBinding.swift`'s own `precondition` traps when it is empty. |

## Localization

Every user-facing string below is an AppKit `String` literal assigned to
`toolTip`, `title`, or an `NSImage`'s `accessibilityDescription` — never a
`LocalizedStringKey`, `NSLocalizedString`, or a String Catalog lookup — so
none of them can be localized without a source change; each would need a
localization key routed through this app's existing localization
mechanism, the same way any other user-facing AppKit string in the
framework is externalized.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal) | "Top" / "Left" / "Bottom" / "Right" | `SpacingEdge.displayName`, used inside every edge's field/arrow tooltip |
| (none — literal) | "{Edge} — points between the edge and what is inside it" | Tooltip on an edge's number field and stepper |
| (none — literal) | "More {edge} space" / "Less {edge} space" | Tooltip, and the arrow image's accessibility description, on an edge's grow/shrink arrows |
| (none — literal) | "side-by-side panes" / "stacked panes" | `SpacingGutter.displayName`, used inside a gutter's arrow tooltip |
| (none — literal) | "Points between two panes side by side. The gap is shared, so this is the whole gap." / the row-stacked equivalent | Tooltip on a gutter's number field and stepper |
| (none — literal) | "Narrower gap between {panes}" / "Wider gap between {panes}" | Tooltip, and accessibility description, on a gutter's narrow/wide arrows |
| (none — literal) | "Reset" | Reset button title |
| (none — literal) | "Set every number here back to zero" | Reset button tooltip |

## Accessibility Options

- **Reduce Motion**: Not applicable — source contains no animation,
  transition, or `NSAnimationContext`/`animator()` call; every redraw and
  layout pass (`needsDisplay`, `needsLayout`) is an instantaneous property
  assignment applied on the next display cycle, so there is no motion for a
  Reduce Motion substitute to replace.
- **Increase Contrast**: See the open question on minimum-contrast-ratio —
  `SemanticPalette`
  (`external/agenticdevelopertoolkit/packages/apple/AgenticDeveloperToolkit/Sources/Theme/SemanticPalette.swift`)
  exposes no Increase-Contrast-aware variant of the tokens this file draws
  from, on top of the baseline contrast question raised there; extending
  `SemanticPalette` to derive a higher-contrast border/fill pair from
  `NSWorkspace.accessibilityDisplayShouldIncreaseContrast` would settle
  both.
- **Differentiate Without Color**: Not applicable — the only information
  this control conveys beyond its numbers (which way an arrow moves a line)
  is carried by arrow-glyph shape and screen position; every arrow shares
  the same accent tint (`contentTintColor`) regardless of direction, so
  there is no color-only signal to duplicate.

## Privacy

- **Data collected**: None beyond the spacing numbers themselves — window/
  pane layout preferences, not personal or sensitive data — and this file
  only holds them in memory as `value`.
- **Storage**: Not applicable to this file — `SpacingControl` performs no
  read or write to disk, `UserDefaults`, or any other store. Persistence,
  when the control is used via `SpacingControl.boundToSettings`, is owned
  by `SpacingSettingsBinding` writing to `UserSetting<Int>`, a separate
  type outside this recipe's scope (see `pane-spacing` for one such
  settings-backed store).
- **Transmission**: Not applicable — no networking call appears anywhere in
  this file.
- **Retention**: Not applicable within this file — the view retains only
  its own subviews, its `value`, and (when bound) its
  `retainedBinding`, for its own lifetime; it persists nothing beyond that
  itself.

