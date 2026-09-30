<!-- leaf: implement-general-view-2/tab-pane-view--test-vectors · source: tab-pane-view.md -->

# TabPaneView

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
| tab-pane-020 | content-size-grows-with-recession-slack | Compare `contentSize` on a `.top` edge vs. a `.left` edge, both with identical content sized so the stack's `fittingSize` lands clear of both the `240`–`340pt` width floor/ceiling and the `136pt` height floor on either edge | The `.left` edge's `contentSize` is exactly `2 × 12 = 24pt` larger than the `.top` edge's, on both width and height |
| tab-pane-021 | front-card-defined-by-zero-depth | Set `stackDepth = 0`, then `stackDepth = 1` | `isFrontCard` reads `true`, then `false` (verified indirectly via `cardFillColor`) |
| tab-pane-022 | depth-change-applies-only-on-change | Record `cardFillColor`, `cardBorderColor`, and `runningMoveAnimationKeys`, then set `stackDepth = 1` when it is already `1` | All three are unchanged afterward: no new animation keys appear and the colors are identical to the values recorded before the redundant set |
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
| tab-pane-037 | depth-animation-settles-pending-layout-first | Resize the card without calling `layoutSubtreeIfNeeded()` (leaving a pending layout), then change `stackDepth` on a windowed view | The running animation's `fromValue` (`background`'s presentation frame at the animation's start) equals the frame the pending layout would have produced, not the frame from before the resize — no stale frame is animated from |
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
| tab-pane-051 | context-menu-provider-is-optional | Leave `contextMenuProvider == nil` (never assigned); call `menu(for: event)` | Returns `super.menu(for: event)`'s result |
| tab-pane-052 | status-symbols-replace-existing | On a freshly constructed `TabPaneView` with no prior status symbols, call `setStatusSymbols([])` | `statusStack.arrangedSubviews.count == 0`; `statusViews == []` |
