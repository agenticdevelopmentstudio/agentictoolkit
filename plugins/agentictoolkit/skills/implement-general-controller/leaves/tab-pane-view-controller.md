<!-- leaf: implement-general-controller/tab-pane-view-controller · source: tab-pane-view-controller.md -->

**Rules** (cite as `implement-general-controller/tab-pane-view-controller#<slug>`):

- `header-text` MUST
- `session-text` MUST
- `directory-text` MUST
- `branch-visibility` MUST
- `summary-visibility` MUST
- `summary-hidden-by-default` MUST
- `status-symbol-replacement` MUST
- `title-and-preferred-content-size` MUST
- `nil-data-source` MUST
- `selection-and-depth-are-reconciled` MUST
- `front-card-overhangs-the-workspace-edge` MUST
- `behind-card-recedes-from-the-workspace-edge` MUST
- `vertical-edge-recession-accumulates-with-depth` MUST
- `horizontal-edge-recession-is-constant` MUST
- `recession-does-not-increase-past-depth-three` MUST
- `paint-and-text-move-together` MUST
- `depth-change-animates-when-attached-to-a-window` MUST
- `depth-change-is-immediate-when-detached` MUST
- `redundant-depth-set-is-a-no-op` MUST
- `card-width-is-bounded` MUST
- `card-height-has-a-floor-and-grows-with-content` MUST
- `front-and-behind-cards-differ-in-role-and-color` MUST
- `front-and-behind-cards-use-distinct-backgrounds` MUST
- `close-button-sits-on-the-outward-end` MUST
- `close-button-callback` MUST
- `labels-do-not-intercept-clicks` MUST
- `status-glyph-has-an-accessible-label` MUST
- `subviews-carry-tab-scoped-accessibility-identifiers` MUST
- `context-menu-is-delegated` MUST
- `view-controller-does-not-support-storyboard-instantiation` MUST
- `component-is-main-actor-confined` MUST
- `component-does-not-poll-its-data-source` MUST

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

