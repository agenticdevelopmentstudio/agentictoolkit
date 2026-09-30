<!-- leaf: implement-general-view-2/tab-pane-view--part-2 · source: tab-pane-view.md -->

# TabPaneView — continued (part 2)

**Rules** (cite as `implement-general-view-2/tab-pane-view--part-2#<slug>`):

- `accessibility-ids-assigned-per-instance` MUST
- `init-from-coder-unavailable` MUST
- `labels-truncate-by-middle-default` MUST
- `labels-resist-compression-at-low-priority` MUST
- `directory-label-truncates-head` MUST
- `summary-label-truncates-tail` MUST
- `labels-not-selectable` MUST
- `summary-label-hidden-by-default` MUST
- `close-button-configuration` MUST
- `close-action-forwards-to-onclose` MUST
- `header-close-button-placement` MUST
- `header-gap-absorbs-extra-width` MUST
- `content-padding` MUST
- `content-stack-order` MUST
- `header-width-matches-content` MUST
- `spacer-absorbs-extra-height` MUST
- `self-not-pinned-either-axis` MUST
- `wants-layer-on-self-and-boxes` MUST
- `content-size-floors` MUST
- `content-size-grows-with-recession-slack` MUST
- `front-card-defined-by-zero-depth` MUST
- `depth-change-applies-only-on-change` MUST
- `depth-recession-flat-on-horizontal-edge` MUST
- `depth-recession-accumulates-on-vertical-edge` MUST
- `depth-recession-clamps-past-max-stack-depth` MUST
- `front-card-overhangs-workspace` MUST
- `text-stays-inset-on-workspace-side` MUST
- `front-card-palette` MUST
- `behind-card-palette` MUST
- `front-card-agent-label-role` MUST
- `front-card-session-label-role` MUST
- `front-card-secondary-label-roles` MUST
- `close-button-tint-follows-depth` MUST
- `theme-change-repaints-card` MUST
- `animated-only-when-in-window` MUST
- `depth-animation-duration-and-curve` MUST
- `depth-animation-settles-pending-layout-first` MUST
- `context-menu-delegates-to-provider` MUST
- `status-symbols-replace-existing` MUST
- `status-symbol-view-configuration` MUST
- `status-symbol-missing-image-fallback` MUST
- `zero-size-card-draws-nothing` MUST
- `card-path-omits-workspace-side` MUST
- `stroke-inset-by-half-point` MUST
- `reaches-over-workspace-restores-half-point` MUST
- `card-fill-and-border-color-accessors` MUST
- `workspace-overhang-accessor` MUST
- `animation-keys-accessor` MUST
- `onclose-is-optional` MAY
- `context-menu-provider-is-optional` MAY

## Behavioral Requirements

- **accessibility-ids-assigned-per-instance**: `init(edge:tabID:)` MUST assign
  a distinct accessibility identifier to itself (`tab-pane.<uuid>`) and to
  `agentLabel`, `sessionLabel`, `directoryLabel`, `branchLabel`,
  `summaryLabel`, and `closeButton` (each `tab-pane.<field>.<uuid>`), using the
  `tabID` passed to it, so two tabs never share an identifier.
- **init-from-coder-unavailable**: `init?(coder:)` MUST be unavailable; the
  type MUST be constructed only through `init(edge:tabID:)`.
- **labels-truncate-by-middle-default**: `agentLabel`, `sessionLabel`, and
  `branchLabel` MUST use `.byTruncatingMiddle` line breaking (the other two
  text labels start there too, before **directory-label-truncates-head** and
  **summary-label-truncates-tail** override them).
- **labels-resist-compression-at-low-priority**: `agentLabel`, `sessionLabel`,
  `directoryLabel`, `branchLabel`, and `summaryLabel` MUST each set their
  horizontal compression-resistance priority to `.defaultLow`.
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

