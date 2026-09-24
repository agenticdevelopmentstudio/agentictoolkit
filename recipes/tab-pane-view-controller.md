---
id: a30725ca-fa2f-4a04-8cb0-8beddf264a0a
title: TabPaneViewController
domain: agentictoolkit://recipes/tab-pane-view-controller
type: ingredient
version: 1.1.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: AppKit tab-bar item that draws one session as a stacked card - agent,
  status, session, directory, branch, summary - and recedes from the workspace
  edge as it stands further from the selected tab.
platforms:
- swift
- macos
tags:
- tabs
- tab-bar
- view-controller
- card
- macos
- appkit
depends-on: []
related:
- agentictoolkit://recipes/multi-tabbed-view-controller
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references:
- https://developer.apple.com/design/human-interface-guidelines
- https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html
approved-by: ''
approved-date: ''
---

# TabPaneViewController

## Overview

`TabPaneViewController` (`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/TabPane/TabPaneViewController.swift`) is an `open`-hosted, `@MainActor` `NSViewController` that represents one session as a tab-bar item inside `MultiTabbedViewController`, via `TabItem.viewController`. It conforms to `TabBarStackedItem`, so the hosting bar can tell it apart from a plain `TabItem.title` string: it carries selection (`isHighlighted`) and how far it stands from the selected tab (`stackDepth`), and it draws itself as a card in a deck rather than a flat label.

Its `paneView` (a `TabPaneView`) is a self-contained card showing the agent's name and model, live status glyphs, session name, working directory, branch, and an optional summary. The card in front of the deck (`stackDepth == 0`) paints the workspace's own backdrop and outline and physically overhangs the bar's edge by one point, fusing its outline with the workspace's so no seam is visible; every card behind it recedes inward on every side - and, on a vertical bar, recedes further the deeper it stands - reading as a deck of cards turned to whichever one is selected. All content is supplied by a weak `TabPaneDataSource`, fetched only when the owner calls `reload()`; the pane never computes or polls for its own content.

## Behavioral Requirements

- **header-text**: On `reload()`, the component MUST set the agent label to `"\(agent) · \(model)"` when the data source's model name is non-nil, and to the agent name alone when it is nil.
- **session-text**: On `reload()`, the component MUST set the session label's text to the data source's session name.
- **directory-text**: On `reload()`, the component MUST set the directory label's text to the data source's working directory with the current user's home directory prefix replaced by `~`, and MUST leave a path outside the home directory unabbreviated.
- **branch-visibility**: On `reload()`, the component MUST set the branch label's text to the data source's branch when non-nil and MUST hide the branch label when the branch is nil.
- **summary-visibility**: On `reload()`, the component MUST set the summary label's text to the data source's summary when non-nil and MUST hide the summary label when the summary is nil.
- **summary-hidden-by-default**: Before any `reload()` runs, the summary label MUST start hidden.
- **status-symbol-replacement**: On `reload()` (and on every call to `setStatusSymbols(_:)`), the component MUST remove any previously shown status glyphs before adding the new ones, so repeated calls MUST NOT accumulate views.
- **title-and-preferred-content-size**: On `reload()`, the component MUST set its `title` to the session label's text and MUST set `preferredContentSize` to the card's current measured content size.
- **nil-data-source**: `reload()` MUST take no action beyond ensuring the view is loaded when `dataSource` is nil.
- **selection-and-depth-are-reconciled**: The component MUST NOT draw the card as the front card unless `isHighlighted` is `true`, regardless of the `stackDepth` value most recently reported by the hosting bar, including the initial value of `0` before any bar has reported anything. When `isHighlighted` is `true` the card draws at depth `0`; when it is `false` the card draws at a depth of at least `1`, even if `stackDepth` is `0`.
- **front-card-overhangs-the-workspace-edge**: The card at depth `0` MUST have its painted background stand `1` point past the card's own bounds on the side facing the workspace.
- **behind-card-recedes-from-the-workspace-edge**: A card at a depth greater than `0` MUST have its painted background and its text pulled in from the card's bounds on every side, including the side facing the workspace, by an amount proportional to its depth.
- **vertical-edge-recession-accumulates-with-depth**: On a vertical edge (`left` or `right`), the recession at depth *n* (`1` ≤ *n* ≤ `3`) MUST equal `n × 4` points.
- **horizontal-edge-recession-is-constant**: On a horizontal edge (`top` or `bottom`), every card at a depth greater than `0` MUST recede by exactly `4` points, regardless of depth.
- **recession-does-not-increase-past-depth-three**: The component MUST NOT recede a card any further once its depth reaches `3`, even if a greater depth is reported.
- **paint-and-text-move-together**: A change of recession MUST move the card's painted background and its text column by the same amount.
- **depth-change-animates-when-attached-to-a-window**: When the card's view has a non-nil `window`, a change of `stackDepth` MUST animate the move over `0.16` seconds with an ease-out timing curve.
- **depth-change-is-immediate-when-detached**: When the card's view has a nil `window`, a change of `stackDepth` MUST apply the new position immediately, with no animation.
- **redundant-depth-set-is-a-no-op**: Setting `stackDepth` to its current value MUST NOT re-run the depth-change logic or start an animation.
- **card-width-is-bounded**: The card's measured width MUST be no less than `240` points and no more than `340` points, regardless of which edge hosts it.
- **card-height-has-a-floor-and-grows-with-content**: The card's measured height MUST be no less than `136` points and MUST grow to fit its content when the content needs more room.
- **front-and-behind-cards-differ-in-role-and-color**: The component MUST set each label's semantic text role according to whether the card is at depth `0` (front) or a depth greater than `0` (behind):

  | Label | Front role | Behind role |
  |-------|-----------|-------------|
  | Agent | `.accent` | `.primaryText` |
  | Session | `.primaryText` | `.secondaryText` |
  | Directory | `.secondaryText` | `.tertiaryText` |
  | Branch | `.secondaryText` | `.tertiaryText` |
  | Summary | `.secondaryText` | `.tertiaryText` |
- **front-and-behind-cards-use-distinct-backgrounds**: The component MUST paint the front card's background and border in the workspace's own backdrop and outline colors, and MUST paint a behind card's background and border in the bar's own window-background and border colors.
- **close-button-sits-on-the-outward-end**: On the `left` edge, the close button MUST appear as the first (leading) element of the card's header; on every other edge, it MUST appear as the last (trailing) element.
- **close-button-callback**: Clicking the close button MUST invoke the `onClose` closure, when one is set.
- **labels-do-not-intercept-clicks**: The agent, session, directory, branch, and summary labels MUST NOT be selectable, so that a click anywhere over them is left for the enclosing tab item's own click handling rather than starting a text selection.
- **status-glyph-has-an-accessible-label**: Each status glyph the component displays MUST carry the accessibility label supplied with it, independent of its symbol name.
- **subviews-carry-tab-scoped-accessibility-identifiers**: The card and each of its agent, session, directory, branch, summary, and close-button subviews MUST expose an accessibility identifier of the form `tab-pane.<part>.<tabID>`, scoped to the pane's own `tabID`.
- **context-menu-is-delegated**: A right-click (or other menu-triggering event) on the card MUST show the menu the `delegate`'s `tabPane(_:contextMenuFor:)` returns when it is non-nil, and MUST fall back to the standard `NSView` menu when the delegate returns `nil` or is unset.
- **view-controller-does-not-support-storyboard-instantiation**: `TabPaneViewController` MUST NOT be instantiable from an `NSCoder` (e.g. a storyboard or XIB); `init?(coder:)` MUST return `nil`.
- **component-is-main-actor-confined**: All properties and methods that read or mutate the pane's displayed state MUST run on the main actor.
- **component-does-not-poll-its-data-source**: The component MUST NOT re-fetch or observe the data source on its own; content MUST change only in response to an explicit `reload()` call.

## Appearance

- **Corner radius**: None - the card is drawn with square corners on every edge (`TabCardBackgroundView.corners(of:)` traces straight lines between four right-angle points).
- **Padding**: `12` pt top/bottom × `14` pt left/right, inside the card's painted border (`TabPaneView.padding`).
- **Font**: Not set directly by this file; each label is a `ThemedLabel` carrying a semantic text role - `.body` for the agent and session labels, `.caption` for the directory, branch, and summary labels - whose concrete font is resolved by the shared theme system.
- **Background**: Front card (`stackDepth == 0`): the theme's `projectPaneBackdrop` color. Behind card: the theme's `.windowBackground` color.
- **Foreground/Text**: Agent label: `.accent` role when front, `.primaryText` role when behind. Session, directory, branch, and summary labels: their front-card roles (`.primaryText`/`.secondaryText`/`.tertiaryText` per label) when front, and one role step dimmer when behind - directory, branch, and summary all render `.tertiaryText` behind the front card.
- **Border**: `1` pt line, in the theme's `projectPaneOutline` color when front and the theme's `.border` color when behind; drawn open on the side facing the workspace (no line across that side) rather than as a closed rectangle.
- **Shadow**: None - no shadow, elevation, or blur is drawn anywhere in `TabPaneView` or `TabCardBackgroundView`.
- **Min/Max size**: Width clamped between `240` pt (`minWidth`) and `340` pt (`maxWidth`) on every edge. Height floored at `136` pt (`minHeight`) with no maximum, growing to fit content.
- **Status glyph size**: Each status `NSImageView` and the close button are both fixed at `14 × 14` pt, with the SF Symbol rendered at `11` pt, regular weight (`symbolConfiguration`).
- **Recession per step**: `4` pt (`inactiveInset`), accumulating up to `3` steps (`maxStackDepth`) on a vertical edge; a flat `4` pt on a horizontal edge.
- **Workspace overhang**: `1` pt (`workspaceOverlap`) - the width of the workspace's own outline, so the front card's paint exactly covers it.

## States

| State | Appearance change |
|-------|------------------|
| Default (behind, depth ≥ 1) | Bar's window-background fill, border-tone outline, dimmer text roles, receded inward on every side by `4`–`12` pt depending on edge and depth. |
| Front (selected, depth 0) | Workspace backdrop fill, workspace outline color, accent-colored agent label, background overhangs the workspace edge by `1` pt, open border seam disappears into the workspace's own line. |
| Pressed | Not applicable: the card itself has no pressed appearance of its own; the only clickable subview drawn here is the close button, and it defines no pressed/highlighted image state beyond AppKit's default button feedback. |
| Disabled | Not applicable: the source defines no disabled state for the card, its labels, or its close button - `isEnabled` is never set to `false` anywhere in `TabPaneView.swift` or `TabPaneViewController.swift`. |
| Focused | Not applicable to the card as a whole, which draws no focus ring of its own. The close button is a standard `NSButton` and so participates in AppKit's default keyboard-focus-ring appearance; no custom focus appearance is defined in source. |
| Loading | Not applicable: the component has no asynchronous fetch of its own - `reload()` reads already-available data-source values synchronously and has no in-flight state to represent. |
| Branch/summary hidden | Branch and summary rows are removed from visible layout (`isHidden = true`) whenever the data source reports `nil` for that field. |
| Depth mid-transition | While `animatesDepthChanges` is `true`, moving between two depths is a `0.16` s ease-out animation of the paint and text insets, not an instantaneous state. |

## Accessibility

- **Role**: `TabPaneView` sets no explicit `NSAccessibility.Role` of its own (no `setAccessibilityRole` call in source); it is inert content occupying a slot, not itself a control. Selection/tab semantics belong to the hosting bar (a sibling component, `TabBarView`, with its own recipe) via the `TabBarHostedItem`/`TabBarStackedItem` protocols this controller conforms to.
- **Label requirements**: The agent, session, directory, branch, and summary labels expose their own `stringValue` as their accessible content; each status glyph carries an explicit `accessibilityLabel` from `TabPaneStatusSymbol.accessibilityLabel`, independent of its `symbolName`. No single combined label summarizes the whole card - VoiceOver visits each subview individually, in the header/session/directory/branch/summary layout order.
- **Announce state changes**: `TabPaneView` posts no accessibility notification of its own when `stackDepth`/`isHighlighted` changes. Announcing that a tab became selected is the hosting bar's responsibility (it owns the selection semantics for the group), not this file's.
- **Minimum tap target**: The close button's hit area is fixed at `14 × 14` pt (both the button and its image carry explicit `14`-point width/height constraints, with no additional invisible padding) - well under the ~`44 × 44` pt Apple HIG comfortable-target guidance and under WCAG 2.5.8's `24 × 24` CSS px minimum. It is a standalone icon button, not inline text, so the inline-text exemption does not apply.
- **Identifiers**: The card and each of its agent, session, directory, branch, summary, and close-button subviews carry a stable `tab-pane.<part>.<tabID>` accessibility identifier, keyed to the pane's own `tabID` (confirmed by `testAccessibilityIdentifiersCarryTheTabID`).

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| tab-pane-001 | header-text | `dataSource` returns agent `"Claude"`, model `"Fable 5.1"`; call `reload()` | `agentLabel.stringValue == "Claude · Fable 5.1"` (per `testReloadFillsTheLabelsFromTheDataSource`) |
| tab-pane-002 | header-text | `dataSource` returns agent `"Claude"`, model `nil`; call `reload()` | `agentLabel.stringValue == "Claude"` (per `testAModelOfNilShowsOnlyTheAgent`) |
| tab-pane-003 | directory-text | Working directory is under the current user's home, e.g. `~/Projects/worktrees/tabs`; call `reload()` | `directoryLabel.stringValue == "~/Projects/worktrees/tabs"` (per `testWorkingDirectoryUnderHomeIsAbbreviatedWithATilde`) |
| tab-pane-004 | branch-visibility | `dataSource.tabPaneBranch` returns non-nil, then a later `reload()` with the same data source returning `nil` | `branchLabel.isHidden` is `false` after the first `reload()` and `true` after the second (per `testReloadTwiceHidesTheBranchLabelWhenBranchGoesNil`) |
| tab-pane-005 | summary-hidden-by-default | Pane constructed and never reloaded | `summaryLabel.isHidden == true` before any `reload()` (per `testReloadFillsTheLabelsFromTheDataSource`) |
| tab-pane-006 | status-symbol-replacement | Call `setStatusSymbols([one symbol])`, then `setStatusSymbols([one symbol])` again | `statusStack.arrangedSubviews.count == 1` after the second call, not `2` (per `testSetStatusSymbolsTwiceDoesNotAccumulateViews`) |
| tab-pane-007 | card-width-is-bounded | Content short enough that `fittingSize.width + slack` is below `240` pt | `preferredContentSize.width == 240` (per `testShortContentStillMeasuresTheMinimumWidth`) |
| tab-pane-008 | card-width-is-bounded | Content long enough that `fittingSize.width + slack` exceeds `340` pt | `preferredContentSize.width == 340` (per `testPaneWidthIsCappedAtMaxWidth`) |
| tab-pane-009 | card-height-has-a-floor-and-grows-with-content | Content taller than `minHeight` on the `top` edge | `preferredContentSize.height > 136` and matches `paneView.fittingSize.height` within `0.5` pt (per `testTopPaneHeightGrowsToFitOversizedContent`) |
| tab-pane-010 | card-width-is-bounded; card-height-has-a-floor-and-grows-with-content | Content short enough to floor width and height on every edge (the slack that differs by edge is masked once content is at the floor) | All four edges report the same floored `preferredContentSize` (per `testEveryEdgeMeasuresTheSameCard`) |
| tab-pane-011 | selection-and-depth-are-reconciled | Pane never highlighted; `stackDepth` never explicitly set | `agentLabel.role == .primaryText` (behind role) before any highlight (per `testSelectionPromotesTheTextInsteadOfHighlightingIt`) |
| tab-pane-012 | selection-and-depth-are-reconciled | Set `isHighlighted = true` | `agentLabel.role == .accent` (per `testSelectionPromotesTheTextInsteadOfHighlightingIt`) |
| tab-pane-013 | front-and-behind-cards-use-distinct-backgrounds | Card not highlighted vs. highlighted | `cardFillColor`/`cardBorderColor` equal `.windowBackground`/`.border` when behind, and `projectPaneBackdrop`/`projectPaneOutline` when front (per `testAnInactiveCardSitsOnTheBarsPlaneAndTheActiveOneOnTheWorkspaces`) |
| tab-pane-014 | front-card-overhangs-the-workspace-edge; behind-card-recedes-from-the-workspace-edge | Card highlighted vs. not, on every edge | `workspaceOverhang == workspaceOverlap (1)` when front, and `== -inactiveInset (-4)` when behind at depth 1 on every edge (per `testOnlyTheActiveCardReachesOverTheWorkspacesOutline`) |
| tab-pane-015 | behind-card-recedes-from-the-workspace-edge | Highlighted card vs. a card at depth 1 | Behind card's painted frame equals `bounds.insetBy(dx: 4, dy: 4)`, and is smaller than the front card's frame on both axes (per `testACardBehindIsPaintedSmallerThanTheCardInFront`) |
| tab-pane-016 | vertical-edge-recession-accumulates-with-depth | Depths 1, 2, 3 on `left`/`right` edges | Recession is `4`, `8`, `12` pt respectively (per `testEachCardBehindStandsAStepFurtherBackOnAVerticalBar`, `testACardTwoStepsBackIsPaintedTwoStepsSmallerOnAVerticalBar`) |
| tab-pane-017 | horizontal-edge-recession-is-constant | Depths 1, 2, 3 on `top`/`bottom` edges | Recession is `4` pt at every one of those depths (per `testEveryCardBehindStandsTheSameStepBackOnAHorizontalBar`) |
| tab-pane-018 | paint-and-text-move-together | Card moved to a receded depth | `cardTextFrame` moves in by the same inset as `cardPaintFrame` (per `testACardStandingBackTakesItsTextWithIt`) |
| tab-pane-019 | front-card-overhangs-the-workspace-edge | Card at depth 0 | `cardTextFrame == bounds` (text stays inside) while `cardPaintFrame` extends past `bounds` on the workspace side (per `testTheFrontCardsTextStaysInsideTheCardItsPaintReachesOutOf`) |
| tab-pane-020 | depth-change-is-immediate-when-detached | Card not attached to a window; set `stackDepth = 2` | `animatesDepthChanges == false` and `workspaceOverhang` reflects the new depth immediately, with no animation (per `testACardOffScreenTakesItsNewDepthImmediately`) |
| tab-pane-021 | depth-change-animates-when-attached-to-a-window | Card attached to a window; change `stackDepth` | `animatesDepthChanges == true` and `runningMoveAnimationKeys` is non-empty during the transition (per `testACardInAWindowMovesToItsNewDepth`) |
| tab-pane-022 | selection-and-depth-are-reconciled | `isHighlighted` toggled `true` → `false` → `true` with varying `stackDepth` values, including `0` | `workspaceOverhang` never reads as "front" while `isHighlighted == false`, whatever `stackDepth` was last told (per `testADeselectedCardIsNeverTheCardInFrontWhateverDepthItWasTold`) |
| tab-pane-023 | front-and-behind-cards-differ-in-role-and-color | Card constructed (behind, depth ≥ 1) vs. `isHighlighted = true` (front) | `agentLabel.role` is `.primaryText` behind and `.accent` front; `sessionLabel`/`directoryLabel`/`branchLabel` never fall to `.placeholderText` at any depth, holding the dimmer-but-readable behind roles from the front/behind role table (per `testAnInactiveCardsTextStaysAtReadableRoles`, `testSelectionPromotesTheTextInsteadOfHighlightingIt`) |
| tab-pane-024 | close-button-callback | `onClose` set; close button clicked | The closure fires exactly once (per `testClosePressedFiresOnClose`) |
| tab-pane-025 | context-menu-is-delegated | `delegate` set, returns a specific `NSMenu` for a given event | `paneView.menu(for:)` returns that exact menu instance, and the delegate is asked exactly once (per `testContextMenuComesFromTheDelegate`) |
| tab-pane-026 | close-button-sits-on-the-outward-end | Pane constructed on each of the four edges | On `left`, the close button is the header's first view; on `top`/`right`/`bottom`, it is the last (per `testCloseButtonSitsOnTheEndFacingAwayFromTheWorkspace`) |
| tab-pane-027 | subviews-carry-tab-scoped-accessibility-identifiers | Pane constructed with a known `tabID` | Root view and each labeled subview expose `tab-pane.<part>.<tabID>` (per `testAccessibilityIdentifiersCarryTheTabID`) |
| tab-pane-028 | view-controller-does-not-support-storyboard-instantiation | Call `TabPaneViewController(coder:)` | Returns `nil` |
| tab-pane-029 | session-text | `dataSource` returns session name `"tabs"`; call `reload()` | `sessionLabel.stringValue == "tabs"` (per `testReloadFillsTheLabelsFromTheDataSource`) |
| tab-pane-030 | title-and-preferred-content-size | `dataSource` returns session name `"tabs"`; call `reload()` | `title == "tabs"` (`== sessionLabel.stringValue`) and `preferredContentSize == paneView.contentSize`; grounded directly in `reload()`'s `title = paneView.sessionLabel.stringValue; preferredContentSize = paneView.contentSize` (`TabPaneViewController.swift:72-73`) - `preferredContentSize`'s bound/growth behavior is covered separately by tab-pane-007/008/009/010, but no dedicated unit test asserts `title` itself |
| tab-pane-031 | nil-data-source | `dataSource` is `nil`; call `reload()` | `loadViewIfNeeded()` runs but no label, `title`, or `preferredContentSize` is touched - the method returns at `guard let dataSource else { return }` (`TabPaneViewController.swift:59`); no dedicated unit test, since `TabPaneViewControllerTests`/`TabCardStackTests` always assign a `StubSource` |
| tab-pane-032 | redundant-depth-set-is-a-no-op | Card attached to a window; set `stackDepth` to its own current value | `runningMoveAnimationKeys` stays empty and `workspaceOverhang` is unchanged, because `TabPaneView.stackDepth`'s `guard stackDepth != oldValue else { return }` (`TabPaneView.swift:85`) never calls `applyDepth(animated:)`; no dedicated unit test - `testACardInAWindowMovesToItsNewDepth` only exercises an actual change |
| tab-pane-033 | recession-does-not-increase-past-depth-three | Vertical edge; `stackDepth = TabPaneView.maxStackDepth + 4` | `workspaceOverhang == -3 × inactiveInset`, the same as depth `3`, not any larger (per `testEachCardBehindStandsAStepFurtherBackOnAVerticalBar`'s past-the-cap assertion) |
| tab-pane-034 | labels-do-not-intercept-clicks | Card constructed on any edge | `agentLabel.isSelectable`, `sessionLabel.isSelectable`, `directoryLabel.isSelectable`, `branchLabel.isSelectable`, and `summaryLabel.isSelectable` are all `false`, grounded in the `label.isSelectable = false` loop in `TabPaneView.setUp()` (`TabPaneView.swift:210`); no dedicated unit test |
| tab-pane-035 | status-glyph-has-an-accessible-label | `setStatusSymbols([TabPaneStatusSymbol(symbolName: "bolt.fill", accessibilityLabel: "Busy")])` | The resulting `NSImageView`'s accessibility label reads `"Busy"`, independent of `symbolName`, per `image.setAccessibilityLabel(symbol.accessibilityLabel)` (`TabPaneView.swift:136`); no dedicated unit test - `testSetStatusSymbolsTwiceDoesNotAccumulateViews` only counts views, not their labels |
| tab-pane-036 | component-does-not-poll-its-data-source | `dataSource`'s answers change after construction, with no call to `reload()` | No label, `title`, or `preferredContentSize` changes on its own; content changes only appear after an explicit `reload()` call, since `reload()` is the sole call site that reads `dataSource` and no observation/polling path exists in `TabPaneViewController.swift`/`TabPaneView.swift`; confirmed by inspection, no dedicated unit test |
| tab-pane-037 | directory-text | `dataSource` returns a working directory outside the current user's home, e.g. `/tmp/repo/.claude/worktrees/tabs`; call `reload()` | `directoryLabel.stringValue == "/tmp/repo/.claude/worktrees/tabs"`, left unabbreviated (per `testReloadFillsTheLabelsFromTheDataSource`'s `directoryLabel.stringValue.hasSuffix("worktrees/tabs")` assertion against the default outside-home stub path) |
| tab-pane-038 | context-menu-is-delegated | `delegate` is `nil` (or set but returns `nil` for the event); a menu-triggering event fires | `paneView.menu(for:)` falls back to `super.menu(for: event)`, AppKit's standard `NSView` menu, per `contextMenuProvider?(event) ?? super.menu(for: event)` (`TabPaneView.swift:197`); no dedicated unit test - `testContextMenuComesFromTheDelegate` only covers the non-nil path |
| tab-pane-039 | header-text; session-text; branch-visibility; summary-visibility; title-and-preferred-content-size | `reload()` called once with short content (agent `"C"`, no model, session `"s"`, branch `"b"`, no summary), then again after every field changes and grows past `maxWidth` | `agentLabel.stringValue` and `sessionLabel.stringValue`/`branchLabel.stringValue` follow the new values; `summaryLabel.isHidden` flips from `true` to `false` once a summary appears; `preferredContentSize.width` moves from `minWidth` to `maxWidth` between the two calls (per `testReloadTwiceFollowsChangedDataSourceValues`) |

## Edge Cases

- **Null/empty input - model absent**: `tabPaneModelName` returns `nil` → the agent label MUST show the agent name alone, with no separator (per `testAModelOfNilShowsOnlyTheAgent`).
- **Null/empty input - branch/summary absent**: `tabPaneBranch`/`tabPaneSummary` return `nil` → the corresponding label MUST be hidden rather than shown empty.
- **Null/empty input - data source absent**: `dataSource` is `nil` when `reload()` is called → the component MUST take no action beyond `loadViewIfNeeded()`, leaving whatever was last displayed unchanged (`guard let dataSource else { return }`). This is the source's only handling of a missing dependency; no error, placeholder, or logged diagnostic is produced.
- **Boundary values - depth at the recession ceiling**: `stackDepth` at `3` (`maxStackDepth`) or any larger value MUST recede the card by the same amount as depth `3` - recession does not keep growing past that ceiling (`recession(atDepth:)` clamps with `min(depth, maxStackDepth)`).
- **Boundary values - content far below/above the card's natural size**: Content shorter than `minWidth`/`minHeight` MUST still measure at the floor; content wider than `maxWidth` MUST clamp at the cap rather than overflow (`testShortContentStillMeasuresTheMinimumWidth`, `testPaneWidthIsCappedAtMaxWidth`).
- **Redundant state change**: Setting `stackDepth` to its own current value MUST be a no-op - no animation starts and `applyDepth` is not re-run (`guard stackDepth != oldValue else { return }`).
- **Concurrent access**: Not applicable in the general sense - every property and method that touches display state is `@MainActor`-isolated, so the AppKit main-thread queue serializes all access; there is no multi-threaded mutation path to defend against.
- **Error states - dependency unavailable**: The only external dependency is `dataSource`; its absence is handled as described above (no-op), not as a surfaced error. There is no network, database, or file-system dependency in this file to fail.
- **Offline/disconnected state**: Not applicable - the component performs no networking of its own; all content arrives synchronously from `dataSource` calls.
- **Repeated `reload()` with changing values**: Calling `reload()` twice with a data source that has changed its answers between calls MUST update every label, the title, and `preferredContentSize` to the new values on the second call, including newly appearing/disappearing branch or summary text (`testReloadTwiceFollowsChangedDataSourceValues`).
- **View never attached to a window**: A depth change on a pane whose view has never been added to a window's view hierarchy MUST apply immediately with no animation, since there is nothing on screen to animate and an animated constraint would read a stale value if measured right after (`animatesDepthChanges`, `testACardOffScreenTakesItsNewDepthImmediately`).
- **Edge-dependent measurement slack (documented quirk, not a guaranteed invariant)**: `contentSize`'s slack term (`2 × deepestRecession`) is edge-dependent - `24` pt on a vertical edge (`3` steps × `4` pt × `2`) versus `8` pt on a horizontal edge (`1` step × `4` pt × `2`) - so, in principle, the same content could measure a different `preferredContentSize` depending solely on which edge hosts the pane. `deepestRecession` reuses `recession(atDepth: maxStackDepth)`, whose body answers a different question for a vertical edge (how far the deepest of several stacked cards recedes) than for a horizontal edge (a constant single-step recession) - the two questions happen to share one implementation. Every existing call site and test happens to mask this: short content is floored to `minWidth`/`minHeight` and long content is capped at `maxWidth`, regardless of which slack value applied (see tab-pane-010), so the difference has never been observed to change a real layout, but the formula itself is not edge-independent when content sits strictly between the floor and the cap.

## Configuration

Not applicable: the pane exposes no tunable, per-instance configuration options. `edge` and `tabID` (the `init(edge:tabID:)` parameters) are fixed identity set once at construction, not configuration a caller varies for behavior or appearance; every other number that shapes the card (`minWidth`, `maxWidth`, `minHeight`, `workspaceOverlap`, `inactiveInset`, `maxStackDepth`, `depthAnimationDuration`, `padding`) is a compiled-in `static let`, never exposed as an initializer parameter or settable property.

## Deep Linking

Not applicable: `TabPaneViewController` is an embedded tab-bar item shown inside `MultiTabbedViewController`, not an independently addressable destination - no URL scheme, universal link, or route table is referenced anywhere in `TabPaneView.swift` or `TabPaneViewController.swift`.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none - hardcoded literal, no `NSLocalizedString`/string-catalog call) | `Close` | `accessibilityDescription` passed to `NSImage(systemSymbolName:accessibilityDescription:)` for the close button's `xmark.circle.fill` glyph. Per the AppKit-literalness rule, a plain `String` parameter (unlike SwiftUI's `Text`/`Label`, whose literal argument is a `LocalizedStringKey`) is not itself a localization key, so this string is genuinely unlocalized. |

All other visible text - agent name, model name, session name, working directory, branch, and summary - is opaque data supplied by `TabPaneDataSource`, not UI copy authored by this component; localizing that content, if ever needed, is the data source's responsibility, not `TabPaneView`'s.

NEEDS REVIEW: Not implemented in source. The `Close` description is an AppKit
`String` literal with no localization lookup, so VoiceOver reads it in English
only.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | NEEDS REVIEW: Not implemented in source. Behavior undefined. `place(animated:)` wraps the depth-driven recession/overhang move in `NSAnimationContext`/`allowsImplicitAnimation` whenever the card's view has a window, with no check of `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` anywhere in `TabPaneView.swift` or `TabPaneViewController.swift` (confirmed absent by inspection). Because this is a positional/size animation - a slide of the card's paint and text inset, not an opacity-only cross-fade - it falls outside the fade exemption and needs a real check the source does not have. |
| Increase Contrast | Not applicable: `TabPaneView` draws only theme-resolved semantic colors (`.primaryText`, `.secondaryText`, `.tertiaryText`, `.accent`, `.border`, `.windowBackground`, `.projectPaneBackdrop`, `.projectPaneOutline`) obtained from `resolvedThemeScope.palette`; any Increase Contrast adaptation of those values is the palette resolver's responsibility, not a branch this file takes itself. |
| Differentiate Without Color | Supported. A card behind the front one is not distinguished by color alone: it is also drawn measurably smaller and pulled back from the workspace edge (`recession`/`workspaceOverhang`, confirmed by `testACardBehindIsPaintedSmallerThanTheCardInFront`), so size and position remain as independent, non-color cues to which card is selected. |

## Feature Flags

Not applicable: no feature-flag or remote-config lookup (`isEnabled(...)`, `FeatureFlag`, or similar) appears anywhere in `TabPaneView.swift` or `TabPaneViewController.swift`; the component is unconditionally present wherever it is instantiated.

## Analytics

Not applicable: no analytics or telemetry event is emitted anywhere in `TabPaneView.swift` or `TabPaneViewController.swift`.

## Privacy

- **Data collected**: None of its own. The component displays agent name, model name, session name, working directory, branch, and summary that `TabPaneDataSource` supplies; it never gathers, derives, or forwards data beyond what it is handed to render.
- **Storage**: None - displayed values live only as the current `stringValue`/`isHidden` state of in-memory `NSTextField`/`NSImageView` subviews for as long as the view controller exists; nothing is written to disk or `UserDefaults`.
- **Transmission**: None - the component performs no networking; it never sends any of the data it displays anywhere.
- **Retention**: None beyond the pane's own lifetime - display state is replaced wholesale on the next `reload()` and discarded when the view controller is deallocated.

## Logging

Not applicable: no logging call (`os_log`, `Logger`, `print`, or `NSLog`) appears anywhere in `TabPaneView.swift` or `TabPaneViewController.swift`.

## Platform Notes

- **SwiftUI**: Model each pane as a small view value exposing agent/model/session/directory/branch/summary/status plus `isFront: Bool` and `depth: Int`. Render the header as an `HStack` (agent `Text`, status `HStack` of small `Image(systemName:)`, `Spacer()`, close `Button`), reversing element order for the left edge with a conditional array rather than a mirrored layout direction, since only the close button's position changes, not the whole reading order. Drive fill/border/text color from `isFront` via `.foregroundStyle`/`.background`, and express recession as `.padding(edgeSet, CGFloat(min(depth, 3)) * 4)` on a vertical edge or a flat `4` on a horizontal one, wrapped in `withAnimation(.easeOut(duration: 0.16))` gated on whether the view is already inserted into the hierarchy (mirroring `animatesDepthChanges`'s `window != nil` check - an unattached view should set its position with no animation transaction at all). There is no direct SwiftUI equivalent of the one-point workspace overhang; approximate it with a `.padding(edge, -1)` applied to the card's background shape alone, not the whole view, so the overhang does not also push the text.
- **Compose**: Represent the pane as a `@Composable` taking the same data plus `isFront`/`depth` state. Build the header as a `Row` with `Arrangement.SpaceBetween`, reversing only the close button's position for a left-edge-equivalent layout with a conditional element order, not a mirrored `LayoutDirection.Rtl`, since only the close button's position changes, not the whole reading order. Animate recession with `animateDpAsState(targetValue = ..., animationSpec = tween(160, easing = LinearOutSlowInEasing))` applied to a `Modifier.padding` or `Modifier.offset`, mirroring `CAMediaTimingFunction(name: .easeOut)`. Because Compose's `border` modifier always strokes all four sides, reproduce the open-sided outline with a custom `Modifier.drawWithContent` that strokes only the three non-workspace-facing sides via a hand-built `Path`, exactly as `TabCardBackgroundView.cardPath()` traces three sides and skips the fourth.
- **React/Web**: Render the card as a `<div>` with CSS custom properties for background/border color toggled by a `data-front` attribute, and a header using `display: flex; justify-content: space-between`, reversing only the close button's position for a left-edge-equivalent layout with a conditional DOM order, not `flex-direction: row-reverse` on the whole header, since only the close button's position changes, not the whole reading order. Animate the recession with a `transition: inset 160ms cubic-bezier(0, 0, 0.58, 1)` (ease-out) on `inset`/`transform: translate(...)`, applied only once the element is mounted (a freshly mounted card sets its initial inset with no transition class, mirroring the no-animation-when-detached case). Reproduce the three-sided open outline with individual `border-top`/`border-right`/`border-bottom`/`border-left` declarations instead of the `border` shorthand, omitting the workspace-facing side.
- **AppKit / UIKit** (source platform): Source lives in `TabPaneViewController.swift` (controller: identity, data-source-driven `reload()`, `TabBarStackedItem` conformance, `applyDepth()` reconciling selection with depth) and `TabPaneView.swift` (the visual card: geometry constants, `CardSides`/`InsetBox` inset math, `TabCardBackgroundView`'s open-path fill/stroke, and the `NSAnimationContext`-driven move). This is AppKit/macOS-only; no UIKit code path exists. A UIKit port would replace `NSBezierPath`/`draw(_:)` with `UIBezierPath`/`CAShapeLayer`, and would drive the recession move through `UIView.animate` or an explicit `CABasicAnimation` on the constraint's owning view, since UIKit has no `NSAnimationContext`/`allowsImplicitAnimation` equivalent for constraint changes.
- **WinUI 3**: Build the card as a `UserControl` whose visual is a `Microsoft.UI.Xaml.Shapes.Path` with a hand-built `PathGeometry`/`PathFigure` running through the same three corner points `TabCardBackgroundView.corners(of:)` computes - a XAML `Border` always strokes all four sides and cannot leave the workspace-facing side open, so it cannot express this shape directly. Bind the path's `Fill`/`Stroke` brushes to "Front"/"Behind" resource keys switched through a `VisualStateManager` state group. Animate the recession/overhang move with a `Storyboard` containing a `DoubleAnimation` (`Duration="0:0:0.16"`, `EasingFunction` a `QuadraticEase` with `EasingMode="EaseOut"`, mirroring `CAMediaTimingFunction(name: .easeOut)`) targeting a `TranslateTransform` or `Margin`, gated on whether the control is currently in the visual tree - an unloaded control should call `Storyboard.SkipToFill()` to jump rather than animate, mirroring `animatesDepthChanges`'s `window != nil` check. Lay out the header in a `Grid` with the close `Button` placed via `Grid.Column`/`HorizontalAlignment` depending on edge, its `Width`/`Height` fixed at `14` (not `Padding`) to match the fixed hit area, and size each status glyph's `FontIcon` at `11`px to mirror the SF Symbol's `pointSize`. Bind `AutomationProperties.AutomationId` to `"tab-pane." + tabId` (and `.agent.`/`.session.`/`.directory.`/`.branch.`/`.summary.`/`.close.` per sub-control) through a converter, matching the `accessibilityID` scheme.

## Design Decisions

**Decision**: An unhighlighted card's drawn depth is clamped to at least `1` (`max(1, stackDepth)`) rather than trusting `stackDepth` directly, including its own default value of `0`.
**Rationale**: Per `applyDepth()`'s own doc comment, the `max` "is what keeps [selection and depth] from contradicting each other: a card that is not the selected one is never the card in front, whatever depth it was last told - including the initial zero, before any bar has said anything," because the hosting bar communicates selection and depth as two independent signals that can arrive in either order.
**Approved**: pending

**Decision**: A card with no window takes a new depth immediately and without animation, while a card in a window animates the move.
**Rationale**: Per `animatesDepthChanges`'s doc comment, "a card with no window is not on screen: there is nothing to watch move, and an animated constraint reads its old value until the animation ends," so measuring an off-screen card immediately after a depth change would read a stale, mid-animation value instead of the settled one.
**Approved**: pending

**Decision**: On a horizontal edge every card behind the front one recedes by exactly one step, while on a vertical edge the recession accumulates per depth up to `maxStackDepth`.
**Rationale**: Per `recession(atDepth:)`'s doc comment, a horizontal bar "lays its cards out along their long side" with no column to fan them down, so there is nothing for a deeper card to recede further into, whereas a vertical bar's cards overlap down a column and can visually "fan away" like a deck.
**Approved**: pending

**Decision**: The card's open-sided background stroke insets its three drawn sides by `0.5` pt but gives the workspace-facing side its half-point back while the card is in front.
**Rationale**: Per `strokeBounds()`'s doc comment, a `1` pt line otherwise straddles the view's own edge; while the front card's paint reaches out over the workspace's outline, "the fill and the two side strokes have to run all the way out through the overhang," or a visible seam would appear where the two surfaces are meant to read as one.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | partial | Accessibility |
| [reduced-motion](agenticdevelopercookbook://compliance/accessibility#reduced-motion) | failed | Accessibility |
| [touch-target-size](agenticdevelopercookbook://compliance/accessibility#touch-target-size) | failed | Accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | Internationalization |

`screen-reader-support` and `keyboard-navigable` are `partial` because the card has no focus behavior or accessibility role of its own, no combined accessibility label across its fields, and the close button's `accessibilityDescription` is an unlocalized literal (see **close-button-callback** and the open question in Localization above); `reduced-motion` and `touch-target-size` are `failed` on the confirmed absence of a Reduce Motion check and a fixed `14`pt close-button hit area below the 44pt minimum; `string-externalization` is `failed` on the hardcoded `Close` literal.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed requirements to subject-only names, merged the duplicate selection/depth requirements, added an explicit per-label role/color table, fixed frontmatter references and moved the misplaced cookbook link to `related`, added missing test vectors and corrected several test-vector-to-requirement mappings, moved the edge-dependent measurement quirk from Design Decisions to Edge Cases, reformatted Design Decisions to the bold three-line form, deleted leftover template instructions, corrected Platform Notes for Compose/React header reordering and Compose's easing curve, and marked two Compliance checks `partial` with a supporting sentence |
| 1.1.1 | 2026-09-23 | Mike Fullerton | Compliance: removed rows for checks absent from the cookbook catalog, remapped reduce-motion-support to reduced-motion |
