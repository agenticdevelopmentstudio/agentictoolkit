---
id: d906afe1-a621-42f1-87c5-c71ec9d43c1e
title: TabPaneView
domain: agentictoolkit://recipes/tab-pane-view
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: AppKit card view for one tab in a MultiTabbedViewController edge bar - sizes,
  colors, and animates between front and stacked-behind depths.
platforms:
- swift
- macos
tags:
- tabs
- tab-bar
- card
- layout
- macos
- appkit
depends-on: []
related:
- agentictoolkit://recipes/multi-tabbed-view-controller
references:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
- https://developer.apple.com/design/human-interface-guidelines/
approved-by: ''
approved-date: ''
---

# TabPaneView

## Overview

`TabPaneView` is a `final`, `@MainActor` `NSView` drawn as one card in an edge
bar of [MultiTabbedViewController](agentictoolkit://recipes/multi-tabbed-view-controller):
a stacked block, the same arrangement on all four edges, showing a session's
agent/model name, status symbols, session name, working directory, branch, and
an optional summary. It is the `view` of `TabPaneViewController`, which hosts
it as a `TabItem.viewController` and drives its `stackDepth`/`isHighlighted`
through `TabBarStackedItem`. The card in front (`stackDepth == 0`) paints what
the workspace paints, in the workspace's own outline color, and overhangs the
bar by one point to cover the line the workspace draws down that side, so one
unbroken line runs around the active card and the workspace it belongs to. A
card behind stops short of its own edge instead, leaving the workspace's line
whole, and — on a vertical (left/right) edge only — recedes further with every
step of depth, so a column of cards reads as a deck turned to the selected
tab.

## Behavioral Requirements

- **accessibility-ids-assigned-per-instance**: `init(edge:tabID:)` MUST assign
  a distinct accessibility identifier to itself (`tab-pane.<uuid>`) and to
  `agentLabel`, `sessionLabel`, `directoryLabel`, `branchLabel`,
  `summaryLabel`, and `closeButton` (each `tab-pane.<field>.<uuid>`), using the
  `tabID` passed to it, so two tabs never share an identifier.
- **init-from-coder-unavailable**: `init?(coder:)` MUST be unavailable; the
  type MUST be constructed only through `init(edge:tabID:)`.
- **labels-truncate-by-middle-default**: `agentLabel`, `sessionLabel`,
  `directoryLabel`, `branchLabel`, and `summaryLabel` MUST default to
  `.byTruncatingMiddle` line breaking.
- **labels-resist-compression-at-low-priority**: The same five labels MUST set
  their horizontal compression-resistance priority to `.defaultLow`.
- **directory-label-truncates-head**: `directoryLabel` MUST override its line
  break mode to `.byTruncatingHead`.
- **summary-label-truncates-tail**: `summaryLabel` MUST override its line
  break mode to `.byTruncatingTail`.
- **labels-not-selectable**: All five text labels MUST have `isSelectable =
  false`, so a pointer-down on a label's own frame is not consumed by
  beginning a text selection and instead reaches whatever hosts this card's
  tab-selection handling.
- **summary-label-hidden-by-default**: `summaryLabel` MUST start hidden
  (`isHidden = true`) when the view is set up.
- **close-button-configuration**: `closeButton` MUST use the `xmark.circle.fill`
  SF Symbol with `imagePosition = .imageOnly`, no bezel (`isBordered = false`,
  `bezelStyle = .inline`), and a fixed `14×14pt` frame.
- **close-action-forwards-to-onclose**: Component MUST invoke `onClose?()`,
  and nothing else, when `closeButton`'s action fires.
- **header-close-button-placement**: `makeHeader()` MUST place `closeButton`
  at the header's leading end when `edge == .left` and at its trailing end for
  every other edge.
- **header-gap-absorbs-extra-width**: The invisible spacer between the
  agent/status group and `closeButton` MUST hug and resist horizontal
  compression at priority `1`, so it — not `agentLabel` or `statusStack` —
  absorbs the header's extra width.
- **content-padding**: `content`'s `edgeInsets` MUST equal `top: 12, left: 14,
  bottom: 12, right: 14`.
- **content-stack-order**: `content`'s arranged subviews MUST be, in order:
  the header, `sessionLabel`, `directoryLabel`, `branchLabel`, `summaryLabel`,
  and a trailing spacer.
- **header-width-matches-content**: Component MUST constrain the header's
  width equal to `content`'s width minus `26pt` (the sum of `content`'s own
  left and right edge insets).
- **spacer-absorbs-extra-height**: The trailing spacer in `content` MUST hug
  and resist vertical compression at priority `1`, so it — not the five text
  lines — absorbs any height the card has beyond what its content needs.
- **self-not-pinned-either-axis**: Component MUST NOT constrain its own width
  or height to a fixed or computed value; both axes are left to the hosting
  bar (cross axis) and to AppKit's own `preferredContentSize` constraint
  (length axis).
- **wants-layer-on-self-and-boxes**: `self`, `background`, and `content` MUST
  each have `wantsLayer = true` set during `setUp()`.
- **content-size-floors**: `contentSize` MUST be no narrower than `240pt`
  (`minWidth`), no wider than `340pt` (`maxWidth`), and no shorter than
  `136pt` (`minHeight`), regardless of the stack's own fitting size.
- **content-size-grows-with-recession-slack**: `contentSize` MUST add `2 ×
  deepestRecession` (twice the recession at `maxStackDepth`) to the stack's
  fitting width and height before applying the floors above.
- **front-card-defined-by-zero-depth**: `isFrontCard` MUST be true if and only
  if `stackDepth == 0`.
- **depth-change-applies-only-on-change**: Setting `stackDepth` to its current
  value MUST NOT re-run `applyDepth(animated:)`; only an actual change of
  value MUST trigger it.
- **depth-recession-flat-on-horizontal-edge**: On a `.top` or `.bottom` edge,
  `recession(atDepth:)` MUST return exactly `4pt` (`inactiveInset`) for any
  depth greater than zero, however large that depth is.
- **depth-recession-accumulates-on-vertical-edge**: On a `.left` or `.right`
  edge, `recession(atDepth:)` MUST return `4pt` per step of depth: `4pt` at
  depth `1`, `8pt` at depth `2`, `12pt` at depth `3`.
- **depth-recession-clamps-past-max-stack-depth**: On a `.left` or `.right`
  edge, `recession(atDepth:)` MUST return the same `12pt` for any depth of `3`
  or greater (`min(depth, maxStackDepth)`).
- **front-card-overhangs-workspace**: When `isFrontCard` is true, the card's
  painted background MUST extend `1pt` (`workspaceOverlap`) past the card's
  own bounds on the side facing the workspace.
- **text-stays-inset-on-workspace-side**: The card's text column (`content`)
  MUST remain inset by `recession` on the workspace-facing side even while
  `isFrontCard` is true and the painted background overhangs that side.
- **front-card-palette**: When `isFrontCard` is true, the card's background
  fill MUST use the resolved theme's `projectPaneBackdrop` color and its
  border MUST use `projectPaneOutline`.
- **behind-card-palette**: When `isFrontCard` is false, the card's background
  fill MUST use the `windowBackground` role and its border MUST use the
  `border` role.
- **front-card-agent-label-role**: `agentLabel.role` MUST be `.accent` when
  `isFrontCard` is true and `.primaryText` when it is false.
- **front-card-session-label-role**: `sessionLabel.role` MUST be
  `.primaryText` when `isFrontCard` is true and `.secondaryText` when it is
  false.
- **front-card-secondary-label-roles**: `directoryLabel.role`,
  `branchLabel.role`, and `summaryLabel.role` MUST each be `.secondaryText`
  when `isFrontCard` is true and `.tertiaryText` when it is false.
- **close-button-tint-follows-depth**: `closeButton.contentTintColor` MUST be
  the `.secondaryText` role color when `isFrontCard` is true and the
  `.tertiaryText` role color when it is false.
- **theme-change-repaints-card**: Component MUST reapply `applyDepth()`
  whenever the active theme changes (registered via `observeTheme` in
  `setUp()`), so the card's colors track the palette live.
- **animated-only-when-in-window**: `animatesDepthChanges` MUST be true only
  while the view has a non-nil `window`.
- **depth-animation-duration-and-curve**: An animated depth change MUST run
  over `0.16s` (`depthAnimationDuration`) using an `easeOut`
  `CAMediaTimingFunction`.
- **depth-animation-settles-pending-layout-first**: Before starting an
  animated depth change, component MUST force any outstanding layout to
  complete (`layoutSubtreeIfNeeded()`) before opening the animation group.
- **context-menu-delegates-to-provider**: `menu(for:)` MUST return
  `contextMenuProvider?(event)` when a provider is set and returns non-nil,
  and MUST fall back to `super.menu(for:)` otherwise.
- **status-symbols-replace-existing**: `setStatusSymbols(_:)` MUST remove
  every previously added status image view from `statusStack` before adding
  the views for the new symbol list.
- **status-symbol-view-configuration**: Each status symbol's `NSImageView`
  MUST render its SF Symbol at `11pt`, `.regular` weight, in a fixed
  `14×14pt` frame, and MUST carry the symbol's `accessibilityLabel` as its own
  accessibility label.
- **status-symbol-missing-image-fallback**: `setStatusSymbols(_:)` MUST
  substitute an empty `NSImage()` when `NSImage(systemSymbolName:)` fails to
  resolve a symbol name, rather than crashing or leaving a nil image.
- **zero-size-card-draws-nothing**: `TabCardBackgroundView.draw(_:)` MUST draw
  nothing when its stroke bounds have zero or negative width or height.
- **card-path-omits-workspace-side**: The card's painted fill and stroke MUST
  trace only the three sides other than the one facing the workspace; the
  workspace-facing side MUST remain visually open, with no stroke drawn along
  it.
- **stroke-inset-by-half-point**: The card's three stroked sides MUST be
  inset `0.5pt` from the view's bounds, so the `1pt` stroke lands fully inside
  the card.
- **reaches-over-workspace-restores-half-point**: When `reachesOverWorkspace`
  is true, the workspace-facing side of the stroke bounds MUST be extended
  back out by that same `0.5pt`, so the fill and the two side strokes run
  flush through the overhang with no seam against the workspace's own line.
- **card-fill-and-border-color-accessors**: `cardFillColor` and
  `cardBorderColor` MUST report exactly the colors currently painted on
  `background` (`fillColor`/`borderColor`).
- **workspace-overhang-accessor**: `workspaceOverhang` MUST report `0` before
  `cardSides` exists and MUST otherwise report `CardSides`'s current
  `workspaceOverhang`.
- **animation-keys-accessor**: `runningMoveAnimationKeys` MUST report the
  union of `background`'s and `content`'s own `CALayer` animation keys.
- **onclose-is-optional**: Component MAY be left with `onClose == nil`; a
  press of `closeButton` then has no observable effect beyond calling a `nil`
  closure.
- **context-menu-provider-is-optional**: Component MAY be left with
  `contextMenuProvider == nil`, in which case `menu(for:)` always falls back
  to `super.menu(for:)`.

## Appearance

- **Corner radius**: Not applicable — `TabCardBackgroundView.corners(of:)`
  traces straight line segments only; no rounded-rect or arc API is used
  anywhere in source, so every corner is square.
- **Padding**: `content.edgeInsets`: `top: 12, left: 14, bottom: 12, right:
  14` (`TabPaneView.padding`). `content.spacing`: `6pt` between arranged
  subviews. `statusStack.spacing`: `2pt` between status symbols. The header's
  own `NSStackView` spacing: `6pt` between the agent label, status stack,
  gap, and close button.
- **Font**: `agentLabel` and `sessionLabel` use `TextRole.body` (base `13pt`,
  `.regular` weight, per `ThemeTypography.font(for:)` — scales with the
  active theme's `sizeScale`). `directoryLabel`, `branchLabel`, and
  `summaryLabel` use `TextRole.caption` (base `11pt`, `.regular` weight, same
  scaling).
- **Background**: `isFrontCard == true`: the resolved palette's
  `projectPaneBackdrop` color. `isFrontCard == false`: the `windowBackground`
  role.
- **Foreground/Text**: `isFrontCard == true`: `agentLabel` in `.accent`;
  `sessionLabel` in `.primaryText`; `directoryLabel`/`branchLabel`/
  `summaryLabel` in `.secondaryText`; `closeButton.contentTintColor` in
  `.secondaryText`. `isFrontCard == false`: `agentLabel` in `.primaryText`;
  `sessionLabel` in `.secondaryText`; the remaining three labels and
  `closeButton.contentTintColor` in `.tertiaryText`.
- **Border**: `1pt` stroke (`TabCardBackgroundView.draw(_:)`,
  `path.lineWidth = 1`) in `projectPaneOutline` (front) or `border` (behind),
  traced along three sides only — the side facing the workspace is left open.
- **Shadow**: Not applicable — `TabCardBackgroundView.draw(_:)` only fills and
  strokes a path; no `NSShadow` or layer shadow property is set anywhere in
  source.
- **Min/Max size**: Card width: `240pt`–`340pt` (`minWidth`/`maxWidth`).
  Card height: `≥ 136pt` (`minHeight`), unbounded above. `closeButton` and
  each status `NSImageView`: fixed `14×14pt` frame. Status symbol glyphs
  render at `11pt`, `.regular` weight (`symbolConfiguration`); `closeButton`'s
  glyph carries no explicit `symbolConfiguration` and renders at AppKit's
  default button-image size within its `14×14pt` frame.

## States

| State | Appearance change |
|-------|------------------|
| Default | — |
| Front (`stackDepth == 0`) | Background = `projectPaneBackdrop`, border = `projectPaneOutline`, `agentLabel` = `.accent`, `sessionLabel` = `.primaryText`, the other three labels and the close tint = `.secondaryText`; painted background overhangs the workspace-facing side by `1pt`; text stays inset by `0`. |
| Behind, horizontal edge (`stackDepth > 0`, `.top`/`.bottom`) | Background = `windowBackground`, border = `border`, `agentLabel` = `.primaryText`, the rest and the close tint = `.tertiaryText`; card and text pulled in `4pt` on every side, flat regardless of depth. |
| Behind, vertical edge (`stackDepth` 1–3, `.left`/`.right`) | Same palette as "Behind" above; card and text pulled in `4pt` per step of depth, up to `12pt` at depth `3` and beyond, so deeper cards read visibly smaller and further back. |
| Depth transition (view in a window) | The recolor/reposition above animates over `0.16s` with an `easeOut` curve rather than jumping; off-screen (`window == nil`) it jumps. |
| Pressed | Not applicable: `TabPaneView` overrides no mouse-tracking method and defines no pressed appearance; a click is a hosting view's concern (`TabItemHostView`, documented in the `multi-tabbed-view-controller` recipe), not this view's. |
| Disabled | Not applicable: no `isEnabled`, disabled tint, or disabled appearance is defined anywhere in source; a tab card that exists is always drawn at full strength. |
| Focused | Not applicable: no custom focus-ring or focused appearance is defined; `closeButton`'s `focusRingType` is left at its AppKit default, and no other subview declares `acceptsFirstResponder`. |
| Loading | Not applicable: every operation in this file (`setStatusSymbols`, `reload`-driven property sets, depth changes) is synchronous; source defines no loading/pending indicator. |

## Accessibility

- **Role/trait**: NEEDS REVIEW: Not implemented in source. Behavior
  undefined. `TabPaneView` sets an `accessibilityIdentifier` on itself and on
  each subview (for UI-test addressing) but no `accessibilityRole`, and does
  not mark itself an accessibility element or group its children into one.
  What is missing: whether a VoiceOver user should hear this card as one
  grouped element (with a computed summary label) rather than as five
  separate, individually-focused static-text elements in sequence with no
  indication that they describe one tab. What would settle it: a VoiceOver
  pass over a real tab bar, deciding whether to add
  `isAccessibilityElement`/`accessibilityChildren()` grouping (as
  `TabButton` does in `TabBarView.swift`, per the `multi-tabbed-view-controller`
  recipe) or an explicit decision that per-label reading is acceptable here.
- **Label requirements**: `closeButton`'s image carries `accessibilityDescription:
  "Close"` (see Localization). Each status `NSImageView` carries the caller-supplied
  `TabPaneStatusSymbol.accessibilityLabel` via `setAccessibilityLabel(_:)`.
  `agentLabel`, `sessionLabel`, `directoryLabel`, `branchLabel`, and
  `summaryLabel` receive no explicit `accessibilityLabel` call in this file;
  VoiceOver falls back to each `NSTextField`'s own `stringValue`, AppKit's
  default for a plain label control.
- **Announce state changes**: NEEDS REVIEW: Not implemented in source.
  Behavior undefined. `applyDepth()` recolors and repositions the card
  whenever it becomes or stops being the front card, but nothing in
  `TabPaneView.swift` posts an `NSAccessibility.post(element:notification:)`
  (or any other accessibility notification) when that happens. What is
  missing: whether a VoiceOver user tracking a different element is told this
  card's selection state changed when no click of their own caused it. What
  would settle it: a VoiceOver pass exercising a programmatic depth change, or
  an explicit decision that the hosting bar's own announcement (if any) is
  sufficient.
- **Minimum tap target**: `closeButton`'s hit area is a fixed `14×14pt`
  (`closeButton.widthAnchor`/`heightAnchor`). macOS is a pointer-driven
  desktop platform; the `44×44pt` (iOS) / `48×48dp` (Android) touch-target
  minimums do not apply directly to this source and instead inform the
  touch-platform translations in Platform Notes.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| tab-pane-001 | accessibility-ids-assigned-per-instance | Construct `TabPaneView(edge: .top, tabID: id)` | `view.accessibilityIdentifier() == "tab-pane.\(id)"`; `agentLabel.accessibilityIdentifier() == "tab-pane.agent.\(id)"` (and likewise for the other four fields and `closeButton`) |
| tab-pane-002 | init-from-coder-unavailable | Attempt to call `TabPaneView(coder:)` from Swift source | Does not compile |
| tab-pane-003 | labels-truncate-by-middle-default | Construct a `TabPaneView` | `agentLabel.lineBreakMode == .byTruncatingMiddle`; same for `sessionLabel`, `branchLabel` |
| tab-pane-004 | labels-resist-compression-at-low-priority | Construct a `TabPaneView` | `agentLabel.contentCompressionResistancePriority(for: .horizontal) == .defaultLow` |
| tab-pane-005 | directory-label-truncates-head | Construct a `TabPaneView` | `directoryLabel.lineBreakMode == .byTruncatingHead` |
| tab-pane-006 | summary-label-truncates-tail | Construct a `TabPaneView` | `summaryLabel.lineBreakMode == .byTruncatingTail` |
| tab-pane-007 | labels-not-selectable | Construct a `TabPaneView` | `agentLabel.isSelectable == false` (and likewise for the other four labels) |
| tab-pane-008 | summary-label-hidden-by-default | Construct a `TabPaneView`, before any caller sets `summaryLabel` | `summaryLabel.isHidden == true` |
| tab-pane-009 | close-button-configuration | Construct a `TabPaneView` | `closeButton.isBordered == false`; `closeButton.bezelStyle == .inline`; `closeButton.imagePosition == .imageOnly`; its width/height constraints both equal `14` |
| tab-pane-010 | close-action-forwards-to-onclose | Set `onClose = { closed = true }`; simulate `closeButton`'s action | `closed == true` |
| tab-pane-011 | header-close-button-placement | Construct `TabPaneView(edge: .left, ...)` vs. `.right` | `.left`'s header has `closeButton` as its first arranged subview; `.right`'s header has it last |
| tab-pane-012 | header-gap-absorbs-extra-width | Widen the header beyond its content's natural width | The gap view's frame grows; `agentLabel`'s and `statusStack`'s frames do not stretch |
| tab-pane-013 | content-padding | Inspect `content.edgeInsets` | `top == 12`, `left == 14`, `bottom == 12`, `right == 14` |
| tab-pane-014 | content-stack-order | Inspect `content.arrangedSubviews` | Order is `[header, sessionLabel, directoryLabel, branchLabel, summaryLabel, spacer]` |
| tab-pane-015 | header-width-matches-content | Lay out a `TabPaneView` | The header's `widthAnchor` constraint's constant equals `-26` relative to `content.widthAnchor` |
| tab-pane-016 | spacer-absorbs-extra-height | Give a `TabPaneView` more height than its text needs | The trailing spacer in `content` grows; the five text lines stay at the top |
| tab-pane-017 | self-not-pinned-either-axis | Inspect `view.constraints` and `view`'s own `widthAnchor`/`heightAnchor` | No required-priority constraint pins `view`'s width or height directly |
| tab-pane-018 | wants-layer-on-self-and-boxes | Construct a `TabPaneView` | `view.wantsLayer == true`; `background.wantsLayer == true`; `content.wantsLayer == true` |
| tab-pane-019 | content-size-floors | All labels empty, no status symbols, on a `.top` edge | `contentSize.width == 240`; `contentSize.height == 136` |
| tab-pane-020 | content-size-grows-with-recession-slack | Compare `contentSize` on a `.top` edge vs. a `.left` edge with identical content | The `.left` edge's `contentSize` is `2 × 12 = 24pt` larger on each axis (before the min/max clamp) |
| tab-pane-021 | front-card-defined-by-zero-depth | Set `stackDepth = 0`, then `stackDepth = 1` | `isFrontCard` reads `true`, then `false` (verified indirectly via `cardFillColor`) |
| tab-pane-022 | depth-change-applies-only-on-change | Set `stackDepth = 1` when it is already `1` | `applyDepth(animated:)` is not invoked (no layout/color change occurs) |
| tab-pane-023 | depth-recession-flat-on-horizontal-edge | `.top` edge; set `stackDepth` to `1`, then `5` | Card inset is `4pt` in both cases |
| tab-pane-024 | depth-recession-accumulates-on-vertical-edge | `.left` edge; set `stackDepth` to `1`, `2`, `3` | Card inset is `4pt`, `8pt`, `12pt` respectively |
| tab-pane-025 | depth-recession-clamps-past-max-stack-depth | `.left` edge; set `stackDepth` to `3`, then `10` | Card inset is `12pt` in both cases |
| tab-pane-026 | front-card-overhangs-workspace | `.top` edge; set `stackDepth = 0` | `workspaceOverhang == 1` |
| tab-pane-027 | text-stays-inset-on-workspace-side | `.top` edge; set `stackDepth = 0` | `cardTextFrame`'s workspace-facing edge is not offset past the card's slot, while `cardPaintFrame`'s is |
| tab-pane-028 | front-card-palette | Set `stackDepth = 0` | `cardFillColor` equals `palette.nsColor(projectPaneBackdrop)`; `cardBorderColor` equals `palette.nsColor(projectPaneOutline)` |
| tab-pane-029 | behind-card-palette | Set `stackDepth = 1` | `cardFillColor` equals `palette.nsColor(.windowBackground)`; `cardBorderColor` equals `palette.nsColor(.border)` |
| tab-pane-030 | front-card-agent-label-role | Toggle `stackDepth` between `0` and `1` | `agentLabel.role` toggles between `.accent` and `.primaryText` |
| tab-pane-031 | front-card-session-label-role | Toggle `stackDepth` between `0` and `1` | `sessionLabel.role` toggles between `.primaryText` and `.secondaryText` |
| tab-pane-032 | front-card-secondary-label-roles | Toggle `stackDepth` between `0` and `1` | `directoryLabel.role`, `branchLabel.role`, `summaryLabel.role` each toggle between `.secondaryText` and `.tertiaryText` |
| tab-pane-033 | close-button-tint-follows-depth | Toggle `stackDepth` between `0` and `1` | `closeButton.contentTintColor` toggles between the `.secondaryText` and `.tertiaryText` role colors |
| tab-pane-034 | theme-change-repaints-card | Post `ThemeManager.didChangeNotification` with a new palette | `cardFillColor`/`cardBorderColor` update to the new palette's values without any other call |
| tab-pane-035 | animated-only-when-in-window | Change `stackDepth` on a `TabPaneView` not attached to a window, then on one attached to a window | `runningMoveAnimationKeys` stays empty in the first case and non-empty (mid-transition) in the second |
| tab-pane-036 | depth-animation-duration-and-curve | Change `stackDepth` on a windowed view | The running `CAAnimation`'s duration is `0.16` and its timing function matches `easeOut` |
| tab-pane-037 | depth-animation-settles-pending-layout-first | Trigger a pending layout, then change `stackDepth` on a windowed view | `layoutSubtreeIfNeeded()` runs before the animation group opens (view has no stale frame at the animation's start) |
| tab-pane-038 | context-menu-delegates-to-provider | Set `contextMenuProvider = { _ in myMenu }`; call `menu(for: event)` | Returns `myMenu` |
| tab-pane-039 | context-menu-delegates-to-provider | Leave `contextMenuProvider` returning `nil`; call `menu(for: event)` | Returns `super.menu(for: event)`'s result |
| tab-pane-040 | status-symbols-replace-existing | Call `setStatusSymbols([a, b])`, then `setStatusSymbols([c])` | `statusStack.arrangedSubviews.count == 1` after the second call, with no leftover views for `a`/`b` |
| tab-pane-041 | status-symbol-view-configuration | Call `setStatusSymbols([.idle])` | The added `NSImageView`'s frame is `14×14`; its `symbolConfiguration.pointSize == 11`; `accessibilityLabel() == "Idle"` |
| tab-pane-042 | status-symbol-missing-image-fallback | Call `setStatusSymbols` with a symbol whose `symbolName` does not resolve | No crash; the resulting `NSImageView.image` is a non-nil empty `NSImage` |
| tab-pane-043 | zero-size-card-draws-nothing | Force `TabCardBackgroundView`'s bounds to zero size; call `draw(_:)` | No fill or stroke operation is issued (no crash, no drawn path) |
| tab-pane-044 | card-path-omits-workspace-side | `.top` edge card; inspect the drawn path | The path's four points touch only the left, top, and right sides; the bottom (workspace) side has no segment between its two corner points |
| tab-pane-045 | stroke-inset-by-half-point | `.top` edge card, `reachesOverWorkspace == false` | `strokeBounds()` equals `bounds.insetBy(dx: 0.5, dy: 0.5)` |
| tab-pane-046 | reaches-over-workspace-restores-half-point | `.top` edge card, `reachesOverWorkspace == true` | `strokeBounds()`'s bottom edge is extended back out by `0.5pt` relative to the non-overhanging case |
| tab-pane-047 | card-fill-and-border-color-accessors | Set `background.fillColor = .red` | `cardFillColor == .red` |
| tab-pane-048 | workspace-overhang-accessor | Query `workspaceOverhang` before `setUp()` has run (`cardSides == nil`) | Returns `0` |
| tab-pane-049 | animation-keys-accessor | Mid-way through an animated depth change | `runningMoveAnimationKeys` is non-empty |
| tab-pane-050 | onclose-is-optional | Leave `onClose == nil`; press `closeButton` | No crash; no observable side effect |

## Edge Cases

- Null/empty input (MUST): `setStatusSymbols([])` MUST leave `statusStack`
  with no arranged subviews and `statusViews == []`. `contentSize` MUST still
  return at least `240×136pt` even when every label's `stringValue` is empty
  and no status symbols are set, because of the unconditional `min`/`max`
  floor in `contentSize`.
- Boundary values (documented behavior, not a gap): `stackDepth` accepts any
  `Int` with no lower or upper clamp in this file. `recession(atDepth:)`
  treats any depth `≤ 0` as zero recession, while `isFrontCard` requires
  `stackDepth == 0` exactly — so a negative `stackDepth` draws the
  non-front palette (`windowBackground`/`border`/`tertiaryText`) at zero
  inset and zero overhang, a combination no depth of `0` or greater produces.
  See Design Decisions. On a vertical edge, any depth of `3` or more MUST
  produce the same `12pt` recession (`min(depth, maxStackDepth)`).
- Concurrent access: Not applicable — `TabPaneView` is `@MainActor`; every
  mutable property (`stackDepth`, `onClose`, `contextMenuProvider`) and every
  method in this file is confined to the main actor, so source provides no
  path for two threads to mutate one instance at the same time.
- Error states (MUST): `setStatusSymbols(_:)` MUST substitute an empty
  `NSImage()` when `NSImage(systemSymbolName:accessibilityDescription:)`
  returns `nil` for an unrecognized symbol name, rather than crashing.
  `TabCardBackgroundView.draw(_:)` MUST draw nothing when `strokeBounds()` has
  zero or negative width or height, rather than constructing a degenerate
  `NSBezierPath`.
- Offline/disconnected: Not applicable — this view performs no networking of
  any kind; every value it displays is handed to it in-process (by
  `TabPaneViewController.reload()`, outside this source).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stackDepth` | `Int` | `1` | How far back in the stack this card is drawn; `0` means the front (selected) card. |
| `onClose` | `(() -> Void)?` | `nil` | Called when `closeButton`'s action fires. |
| `contextMenuProvider` | `((NSEvent) -> NSMenu?)?` | `nil` | Supplies the menu `menu(for:)` returns; falls back to `super.menu(for:)` when `nil` or when it returns `nil`. |

## Deep Linking

Not applicable: `TabPaneView.swift` defines no URL scheme, `NSUserActivity`,
route, or deep-link handler anywhere in source; the card is constructed and
updated only by direct, in-process calls from `TabPaneViewController`.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — | "Close" | `NSImage(systemSymbolName:accessibilityDescription:)`'s description for `closeButton`'s `xmark.circle.fill` glyph |

NEEDS REVIEW: Not implemented in source. Behavior undefined. "Close" is a
hardcoded English `String` literal passed directly to
`accessibilityDescription`, not routed through `NSLocalizedString` or any
other localization mechanism used in this file. What is missing: a translated
string table entry for this description. What would settle it: adding it to
the app's string catalog/`.strings` file and replacing the literal with a
lookup. (The status symbols' `accessibilityLabel` values, and every label's
displayed text, are caller-supplied data from `TabPaneDataSource`/
`TabPaneStatusSymbol` — like a tab's own title in the `multi-tabbed-view-controller`
recipe, they carry no localization concern of this view's own making.)

## Accessibility Options

- **Reduce Motion**: NEEDS REVIEW: Not implemented in source. Behavior
  undefined. `place(animated:)` slides and resizes the card's paint and text
  boxes (a position *and* size change, not a plain opacity cross-fade) over
  `0.16s` whenever `stackDepth` changes on a windowed view; nothing in
  `TabPaneView.swift` checks `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`
  (or any Reduce Motion signal) before running that animation. What is
  missing: whether a Reduce Motion user should see the depth change apply
  immediately instead of sliding. What would settle it: a decision from the
  theme/accessibility owner on the substitute (an immediate jump, matching the
  `animated: false` path already in `place(animated:)`), or confirmation that
  a `0.16s` slide is short enough to be exempt.
- **Increase Contrast**: Not applicable — every color this component draws
  (`projectPaneBackdrop`, `projectPaneOutline`, `windowBackground`, `border`,
  `.accent`, `.primaryText`, `.secondaryText`, `.tertiaryText`) is a semantic
  palette role; Increase Contrast handling, if any, belongs to the
  theme/palette system this component defers to, not to this file.
- **Differentiate Without Color**: Supported. The front/behind distinction is
  never carried by color alone: a behind card is also drawn smaller and
  further from the workspace (`recession`, `≥ 4pt` on every side) and never
  overhangs the workspace's outline (`workspaceOverhang`), while the front
  card does both — a geometry-based cue that accompanies every color change
  `applyDepth()` makes.

## Feature Flags

Not applicable: no feature-flag or config-gating lookup appears anywhere in
`TabPaneView.swift`; the card behaves identically regardless of any external
flag.

## Analytics

Not applicable: source contains no analytics or telemetry call anywhere in
`TabPaneView.swift`.

## Privacy

- **Data collected**: None by this view itself. It renders caller-supplied
  display strings (agent/model name, session name, working-directory path,
  branch name, summary) and caller-supplied status symbols; it does not
  capture, log, or forward any of it elsewhere.
- **Storage**: In-memory only (`NSTextField.stringValue`, `NSImageView.image`)
  for the life of the view. Nothing in this source persists to disk.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: None beyond the view's own lifetime.

## Logging

Not applicable: source contains no logging call (no `print`, `os_log`, or
`Logger`/`Loggable` reference) anywhere in `TabPaneView.swift`.

## Platform Notes

- **SwiftUI**: Model the open-sided outline as a custom `Shape` (a
  `path(in:)` implementation tracing the same four points
  `TabCardBackgroundView.corners(of:)` does, per edge, and never closing back
  across the workspace-facing side), composed as a `.background`/`.overlay`
  pair (fill, then stroke) behind a `VStack` mirroring `content`'s order
  (header `HStack`, then the four remaining labels, then a `Spacer()` in
  place of the trailing spacer). Drive `isFrontCard`/`recession`/`overhang`
  from a passed-in `depth: Int`, and wrap the shape's frame/offset change in
  `.animation(.easeOut(duration: 0.16), value: depth)` — gated behind
  `@Environment(\.accessibilityReduceMotion)` per the Reduce Motion gap noted
  above. Use `.lineLimit(1)` with `.truncationMode(.middle)`/`.head`/`.tail`
  to match the per-label truncation modes.
- **Compose**: Draw the same open-sided outline with a `Canvas`/`Path` in a
  `Box`, sized by a `Modifier.widthIn(min = 240.dp, max = 340.dp)` /
  `heightIn(min = 136.dp)`. Represent front/behind with an `animateDpAsState`
  (or `animateFloatAsState`) driving inset/offset over `160.milliseconds`
  with an `EaseOut` easing curve, checked against
  `LocalAccessibilityManager`/a Reduce Motion setting equivalent before
  animating. Lay out the header as a `Row` with a `Spacer(Modifier.weight(1f))`
  in place of `gap`, and the remaining lines in a `Column`, each using
  `Modifier.basicMarquee()` or `TextOverflow.Ellipsis` with the matching
  start/middle/end truncation.
- **React/Web**: Build the card as a `<div>` whose `background` fills the
  full rect but whose `border` is set on only three sides (the CSS
  longhands `border-top`/`border-left`/`border-right`, omitting the
  workspace-facing side) — or, for the exact open-path stroke, an inline SVG
  `<path>` built from the same four points. Transition `margin`/`transform`
  over `0.16s ease-out` for the depth change, gated behind a
  `prefers-reduced-motion: reduce` media query per the Reduce Motion gap
  above. Use CSS `text-overflow: ellipsis` for tail truncation, `direction:
  rtl` on an inner span for head truncation (the `directoryLabel` case), and
  a `<button aria-label="Close">` for `closeButton`.
- **AppKit/UIKit** (source platform): Implemented in
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/TabPane/TabPaneView.swift`
  (`TabPaneView`, plus the file-private `InsetBox`, `CardSides`, and
  `TabCardBackgroundView` types), hosted by `TabPaneViewController.swift` in
  the same directory. This is a macOS-only, AppKit `NSView` component with no
  UIKit code path in source. A UIKit port has no first-class analog to an
  `NSBezierPath`-drawn, three-sided open card that overhangs a sibling view by
  a point; it would use a plain `UIView` with a `CAShapeLayer` (a
  `UIBezierPath` built the same four-point, open-path way, `fillColor` and
  `strokeColor` set from the palette) and `UIView.animate(withDuration:)` (or
  `UIViewPropertyAnimator` with an ease-out curve) for the depth transition,
  checking `UIAccessibility.isReduceMotionEnabled` first.
- **WinUI 3** (the reason this recipe exists): There is no single WinUI 3
  control for an open-sided, overhanging tab card, so build it as a
  `UserControl`/`Grid` whose background is a plain `Rectangle`/`Border`
  `Fill` (WinUI's `Border` strokes all four sides at once, so reproduce the
  open workspace-facing side with a `Path`/`Geometry` built from the same
  four corner points `corners(of:)` computes, or by drawing three separate
  `Line`/`Rectangle` strokes and simply omitting the fourth) sized between
  `MinWidth="240" MaxWidth="340" MinHeight="136"`. Drive the front/behind
  recession and the front card's one-pixel overhang with a `Margin` bound to
  a view-model property, animated by a `Storyboard`
  `DoubleAnimation`/`ThicknessAnimation` (`Duration="0:0:0.16"`, an
  `EasingFunction` matching `easeOut`, e.g. `CubicEase EasingMode="EaseOut"`),
  skipped in favor of an immediate `Margin` set when
  `Windows.UI.ViewManagement.UISettings.AnimationsEnabled` (or the app's own
  Reduce Motion setting) is off — mirroring the Reduce Motion gap noted above,
  which this port should not repeat. Swap `Background`/`Foreground`
  `SolidColorBrush`es between the front and behind palettes with a
  `VisualStateManager` `FrontCard`/`BehindCard` state group, the way
  `applyDepth()` swaps palette roles. Lay out the header as a horizontal
  `StackPanel` with a zero-width `Grid` column (`Width="*"`) in place of
  `gap`, followed by a close `Button` styled borderless
  (`Style="{StaticResource TransparentButtonStyle}"` or equivalent), sized
  `14x14`, using the Segoe Fluent Icons `` ("Cancel") glyph, with
  `AutomationProperties.Name="Close"`. Represent the status symbols as a
  horizontal `ItemsRepeater`/`StackPanel` of `14x14` `FontIcon`s, each with
  its own `AutomationProperties.Name` bound to the caller-supplied label.
  Bind `MinWidth`/`MinHeight` growth to the hosted content's measured
  `DesiredSize` plus the recession slack, mirroring `contentSize`.

## Design Decisions

- Decision: `init?(coder:)` is `@available(*, unavailable)` and its body
  returns `nil` rather than calling `fatalError()`.
  Rationale: The `unavailable` attribute already makes this initializer
  uncallable from Swift source, so the body is unreachable in practice;
  returning `nil` here (and in the file-private `TabCardBackgroundView`'s own
  `init?(coder:)`) is what this file does, rather than the `fatalError()`
  pattern used by some other AppKit types in the codebase — noted here per
  source fidelity rather than smoothed over.
  Approved: pending
- Decision: `stackDepth` accepts any `Int` with no clamp, and
  `recession(atDepth:)` treats any non-positive depth as zero recession while
  `isFrontCard` still requires `stackDepth == 0` exactly.
  Rationale: `TabBarStackedItem.stackDepth`'s own doc comment defines depth as
  "0 for the selected item itself, 1 for either neighbour, and on outward" —
  non-negative by contract — and the one caller in this codebase
  (`TabPaneViewController.applyDepth()`) always passes `max(1, stackDepth)` or
  `0`, so a negative depth never currently reaches this view. Nothing in
  `TabPaneView.swift` itself enforces that contract, so the combination is
  recorded here per source fidelity rather than assumed away.
  Approved: pending
- Decision: `recession(atDepth:)` grows with depth only on a vertical
  (`.left`/`.right`) edge; a horizontal (`.top`/`.bottom`) edge gets the same
  flat `4pt` inset at every depth greater than zero.
  Rationale: Per `Edge.isVertical`'s and `TabPaneView.recession`'s own doc
  comments, only a vertical bar lays its cards in a column with room to
  recede down; a horizontal bar's cards sit side by side along their long
  axis with no depth to show, so there is nothing for a second or third step
  to add.
  Approved: pending
- Decision: The card's own view is left unpinned on both axes — no
  self-constraint on width or height.
  Rationale: Per `setUp()`'s inline comment, the cross axis is the hosting
  bar's own required-priority constraint (`TabBarView.rebuildButtons()`) and
  the length axis is AppKit's own priority-501
  `NSViewController.preferredContentSize` constraint, driven by
  `contentSize`; a required self-pin here would restate one of those two
  numbers at required priority and risk an unsatisfiable conflict with
  whichever one wins.
  Approved: pending
- Decision: `contentSize` measures `content.fittingSize`, not the card's own
  `fittingSize`.
  Rationale: Per the property's doc comment, `TabPaneViewController` installs
  AppKit's priority-501 `preferredContentSize` constraints onto the card
  itself, and the labels resist compression at only `.defaultLow` — so asking
  the card for its own `fittingSize` after a first measurement would return
  that first answer again, and a card whose text grows on a later `reload()`
  would never widen. The stack (`content`) carries none of those constraints,
  so it is measured instead.
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [main-actor-confined](agenticdevelopercookbook://compliance/architecture#main-actor-confined) | passed | architecture |
| [theme-token-only-colors](agenticdevelopercookbook://compliance/ui#theme-token-only-colors) | passed | ui |
| [differentiate-without-color](agenticdevelopercookbook://compliance/accessibility#differentiate-without-color) | passed | accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | partial | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | accessibility |
| [live-region-announcements](agenticdevelopercookbook://compliance/accessibility#live-region-announcements) | failed | accessibility |
| [reduce-motion-support](agenticdevelopercookbook://compliance/accessibility#reduce-motion-support) | failed | accessibility |
| [touch-target-size](agenticdevelopercookbook://compliance/accessibility#touch-target-size) | not-applicable | accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | not-applicable | accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | internationalization |

Main-actor-confined passes because `TabPaneView`, `TabCardBackgroundView`,
`CardSides`, and `InsetBox` are all declared `@MainActor`. Theme-token-only-colors
passes because every color painted or read (`projectPaneBackdrop`,
`projectPaneOutline`, `windowBackground`, `border`, `.accent`, `.primaryText`,
`.secondaryText`, `.tertiaryText`) is a semantic palette role, never a raw hex
or system color literal. Differentiate-without-color passes because the
front/behind distinction always carries a geometry cue (`recession`,
`workspaceOverhang`) alongside its color change. Keyboard-navigable is partial
because `closeButton` is a real `NSButton` and gets standard key-view-loop
operability for free, but selecting the card itself has no keyboard path in
this file — that is the hosting `TabItemHostView`'s concern (see the
`multi-tabbed-view-controller` recipe's own `keyboard-navigable: failed`
finding). Screen-reader-support is partial because accessibility identifiers
and status-symbol labels are set explicitly, but the card sets no
`accessibilityRole` and groups nothing for VoiceOver (see Accessibility).
Live-region-announcements and reduce-motion-support are failed for the gaps
documented in Accessibility and Accessibility Options respectively.
Touch-target-size and contrast-ratio are not-applicable because this is a
pointer-driven macOS desktop control, not a touch surface, and its colors are
palette tokens whose contrast is defined outside this source.
String-externalization is failed because `closeButton`'s "Close" accessibility
description is a hardcoded English literal (see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
