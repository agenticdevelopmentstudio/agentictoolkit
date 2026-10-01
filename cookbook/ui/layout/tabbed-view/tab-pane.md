---
id: a30725ca-fa2f-4a04-8cb0-8beddf264a0a
title: Tab Pane
domain: agentictoolkit://cookbook/ui/layout/tabbed-view/tab-pane
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A tab-bar item that draws one session as a stacked card - agent,
  status, session, directory, branch, summary - and recedes from the
  workspace edge as it stands further from the selected tab.
platforms:
- swift
- macos
tags:
- tabs
- tab-bar
- view-controller
- card
depends-on: []
related:
- agentictoolkit://cookbook/ui/layout/tabbed-view
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references:
- https://developer.apple.com/design/human-interface-guidelines
- https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html
approved-by: ''
approved-date: ''
---

# Tab Pane

## Overview

The component represents one session as a tab-bar item inside
[the tabbed view](agentictoolkit://cookbook/ui/layout/tabbed-view). It
conforms to a stacked-item interface, so the hosting bar can tell it apart
from a plain title string: it carries selection (highlighted state) and how
far it stands from the selected tab (stack depth), and it draws itself as a
card in a deck rather than a flat label.

Its pane view is a self-contained card showing the agent's name and model,
live status glyphs, session name, working directory, branch, and an optional
summary. The card in front of the deck (depth `0`) paints the workspace's
own backdrop and outline and physically overhangs the bar's edge by one
point, fusing its outline with the workspace's so no seam is visible; every
card behind it recedes inward on every side - and, on a vertical bar,
recedes further the deeper it stands - reading as a deck of cards turned to
whichever one is selected. All content is supplied by a data source, fetched
only when the owner calls the reload operation; the pane never computes or
polls for its own content.

## Behavioral Requirements

- **header-text**: On reload, the component MUST set the agent label to
  `"\(agent) · \(model)"` when the data source's model name is non-nil, and
  to the agent name alone when it is nil.
- **session-text**: On reload, the component MUST set the session label's
  text to the data source's session name.
- **directory-text**: On reload, the component MUST set the directory
  label's text to the data source's working directory with the current
  user's home directory prefix replaced by `~`, and MUST leave a path
  outside the home directory unabbreviated.
- **branch-visibility**: On reload, the component MUST set the branch
  label's text to the data source's branch when non-nil and MUST hide the
  branch label when the branch is nil.
- **summary-visibility**: On reload, the component MUST set the summary
  label's text to the data source's summary when non-nil and MUST hide the
  summary label when the summary is nil.
- **summary-hidden-by-default**: Before any reload runs, the summary label
  MUST start hidden.
- **status-symbol-replacement**: On reload (and on every replacement of the
  status glyphs), the component MUST remove any previously shown status
  glyphs before adding the new ones, so repeated calls MUST NOT accumulate
  elements.
- **title-and-preferred-content-size**: On reload, the component MUST set
  its title to the session label's text and MUST set its preferred content
  size to the card's current measured content size.
- **nil-data-source**: The reload operation MUST take no action beyond
  ensuring the view is loaded when no data source is set.
- **selection-and-depth-are-reconciled**: The component MUST NOT draw the
  card as the front card unless its highlighted state is `true`, regardless
  of the stack depth value most recently reported by the hosting bar,
  including the initial value of `0` before any bar has reported anything.
  When highlighted, the card draws at depth `0`; when not, the card draws at
  a depth of at least `1`, even if the reported depth is `0`.
- **front-card-overhangs-the-workspace-edge**: The card at depth `0` MUST
  have its painted background stand `1` point past the card's own bounds on
  the side facing the workspace.
- **behind-card-recedes-from-the-workspace-edge**: A card at a depth greater
  than `0` MUST have its painted background and its text pulled in from the
  card's bounds on every side, including the side facing the workspace, by
  an amount proportional to its depth.
- **vertical-edge-recession-accumulates-with-depth**: On a vertical edge
  (left or right), the recession at depth *n* (`1` ≤ *n* ≤ `3`) MUST equal
  `n × 4` points.
- **horizontal-edge-recession-is-constant**: On a horizontal edge (top or
  bottom), every card at a depth greater than `0` MUST recede by exactly `4`
  points, regardless of depth.
- **recession-does-not-increase-past-depth-three**: The component MUST NOT
  recede a card any further once its depth reaches `3`, even if a greater
  depth is reported.
- **paint-and-text-move-together**: A change of recession MUST move the
  card's painted background and its text column by the same amount.
- **depth-change-animates-when-attached-to-a-window**: When the card's view
  has a non-nil window, a change of stack depth MUST animate the move over
  `0.16` seconds with an ease-out timing curve.
- **depth-change-is-immediate-when-detached**: When the card's view has a
  nil window, a change of stack depth MUST apply the new position
  immediately, with no animation.
- **redundant-depth-set-is-a-no-op**: Setting the stack depth to its current
  value MUST NOT re-run the depth-change logic or start an animation.
- **card-width-is-bounded**: The card's measured width MUST be no less than
  `240` points and no more than `340` points, regardless of which edge
  hosts it.
- **card-height-has-a-floor-and-grows-with-content**: The card's measured
  height MUST be no less than `136` points and MUST grow to fit its content
  when the content needs more room.
- **front-and-behind-cards-differ-in-role-and-color**: The component MUST
  set each label's semantic text role according to whether the card is at
  depth `0` (front) or a depth greater than `0` (behind):

  | Label | Front role | Behind role |
  |-------|-----------|-------------|
  | Agent | `.accent` | `.primaryText` |
  | Session | `.primaryText` | `.secondaryText` |
  | Directory | `.secondaryText` | `.tertiaryText` |
  | Branch | `.secondaryText` | `.tertiaryText` |
  | Summary | `.secondaryText` | `.tertiaryText` |
- **front-and-behind-cards-use-distinct-backgrounds**: The component MUST
  paint the front card's background and border in the workspace's own
  backdrop and outline colors, and MUST paint a behind card's background and
  border in the bar's own window-background and border colors.
- **close-button-sits-on-the-outward-end**: On the left edge, the close
  button MUST appear as the first (leading) element of the card's header; on
  every other edge, it MUST appear as the last (trailing) element.
- **close-button-callback**: Clicking the close button MUST invoke the close
  callback, when one is set.
- **labels-do-not-intercept-clicks**: The agent, session, directory, branch,
  and summary labels MUST NOT be selectable, so that a click anywhere over
  them is left for the enclosing tab item's own click handling rather than
  starting a text selection.
- **status-glyph-has-an-accessible-label**: Each status glyph the component
  displays MUST carry the accessibility label supplied with it, independent
  of its symbol name.
- **subviews-carry-tab-scoped-accessibility-identifiers**: The card and each
  of its agent, session, directory, branch, summary, and close-button
  subviews MUST expose an accessibility identifier of the form
  `tab-pane.<part>.<tabID>`, scoped to the pane's own tab ID.
- **context-menu-is-delegated**: A right-click (or other menu-triggering
  event) on the card MUST show the menu the delegate supplies when it is
  non-nil, and MUST fall back to the platform's standard context menu when
  the delegate returns nil or is unset.
- **component-does-not-poll-its-data-source**: The component MUST NOT
  re-fetch or observe the data source on its own; content MUST change only
  in response to an explicit reload call.

## Appearance

- **Corner radius**: None - the card is drawn with square corners on every
  edge; its outline traces straight lines between four right-angle points.
- **Padding**: `12` pt top/bottom × `14` pt left/right, inside the card's
  painted border.
- **Font**: Not set directly by this file; each label carries a semantic
  text role - `.body` for the agent and session labels, `.caption` for the
  directory, branch, and summary labels - whose concrete font is resolved by
  the shared theme system.
- **Background**: Front card (depth `0`): the theme's `projectPaneBackdrop`
  color. Behind card: the theme's `.windowBackground` color.
- **Foreground/Text**: Agent label: `.accent` role when front, `.primaryText`
  role when behind. Session, directory, branch, and summary labels: their
  front-card roles (`.primaryText`/`.secondaryText`/`.tertiaryText` per
  label) when front, and one role step dimmer when behind - directory,
  branch, and summary all render `.tertiaryText` behind the front card.
- **Border**: `1` pt line, in the theme's `projectPaneOutline` color when
  front and the theme's `.border` color when behind; drawn open on the side
  facing the workspace (no line across that side) rather than as a closed
  rectangle.
- **Shadow**: None - no shadow, elevation, or blur is drawn anywhere in this
  component.
- **Min/Max size**: Width clamped between `240` pt (minimum) and `340` pt
  (maximum) on every edge. Height floored at `136` pt with no maximum,
  growing to fit content.
- **Status glyph size**: Each status glyph and the close button are both
  fixed at `14 × 14` pt, with the icon rendered at `11` pt, regular weight.
- **Recession per step**: `4` pt, accumulating up to `3` steps on a vertical
  edge; a flat `4` pt on a horizontal edge.
- **Workspace overhang**: `1` pt - the width of the workspace's own outline,
  so the front card's paint exactly covers it.

## States

| State | Appearance change |
|-------|------------------|
| Default (behind, depth ≥ 1) | Bar's window-background fill, border-tone outline, dimmer text roles, receded inward on every side by `4`–`12` pt depending on edge and depth. |
| Front (selected, depth 0) | Workspace backdrop fill, workspace outline color, accent-colored agent label, background overhangs the workspace edge by `1` pt, open border seam disappears into the workspace's own line. |
| Pressed | Not applicable: the card itself has no pressed appearance of its own; the only clickable subview drawn here is the close button, and it defines no pressed/highlighted image state beyond the platform's default button feedback. |
| Disabled | Not applicable: no disabled state is ever set anywhere in this component - the card, its labels, and its close button are always drawn at full strength. |
| Focused | Not applicable to the card as a whole, which draws no focus ring of its own. The close button is a standard button and so participates in the platform's default keyboard-focus-ring appearance; no custom focus appearance is defined. |
| Loading | Not applicable: the component has no asynchronous fetch of its own - reload reads already-available data-source values synchronously and has no in-flight state to represent. |
| Branch/summary hidden | Branch and summary rows are removed from visible layout (hidden) whenever the data source reports nil for that field. |
| Depth mid-transition | While the card is animating a depth change, moving between two depths is a `0.16` s ease-out animation of the paint and text insets, not an instantaneous state. |

## Accessibility

- **Role**: The pane view sets no explicit accessibility role of its own;
  it is inert content occupying a slot, not itself a control. Selection/tab
  semantics belong to the hosting bar (a sibling component, with its own
  recipe) via the stacked-item interfaces this controller conforms to.
- **Label requirements**: The agent, session, directory, branch, and summary
  labels expose their own text as their accessible content; each status
  glyph carries an explicit accessibility label from its own status-symbol
  value, independent of its symbol name. No single combined label
  summarizes the whole card - the screen reader visits each subview
  individually, in the header/session/directory/branch/summary layout
  order.
- **Announce state changes**: The component posts no accessibility
  notification of its own when the stack depth or highlighted state
  changes. Announcing that a tab became selected is the hosting bar's
  responsibility (it owns the selection semantics for the group), not this
  file's.
- **Minimum tap target**: The close button's hit area is fixed at `14 × 14`
  pt (both the button and its image carry explicit `14`-point width/height
  constraints, with no additional invisible padding) - well under the
  ~`44 × 44` pt comfortable-target guidance and under WCAG 2.5.8's `24 × 24`
  CSS px minimum. It is a standalone icon button, not inline text, so the
  inline-text exemption does not apply.
- **Identifiers**: The card and each of its agent, session, directory,
  branch, summary, and close-button subviews carry a stable
  `tab-pane.<part>.<tabID>` accessibility identifier, keyed to the pane's
  own tab ID.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| tab-pane-001 | header-text | The data source returns agent `"Claude"`, model `"Fable 5.1"`; reload | The agent label reads `"Claude · Fable 5.1"` |
| tab-pane-002 | header-text | The data source returns agent `"Claude"`, model `nil`; reload | The agent label reads `"Claude"` |
| tab-pane-003 | directory-text | The working directory is under the current user's home, e.g. `~/Projects/worktrees/tabs`; reload | The directory label reads `"~/Projects/worktrees/tabs"` |
| tab-pane-004 | branch-visibility | The data source's branch is non-nil, then a later reload with the same data source returning nil | The branch label is shown after the first reload and hidden after the second |
| tab-pane-005 | summary-hidden-by-default | Pane constructed and never reloaded | The summary label is hidden before any reload |
| tab-pane-006 | status-symbol-replacement | Replace the status glyphs with one symbol, then replace them again with one symbol | Only one status glyph remains after the second call, not two |
| tab-pane-007 | card-width-is-bounded | Content short enough that the measured width falls below `240` pt | The preferred content size's width reads `240` |
| tab-pane-008 | card-width-is-bounded | Content long enough that the measured width exceeds `340` pt | The preferred content size's width reads `340` |
| tab-pane-009 | card-height-has-a-floor-and-grows-with-content | Content taller than the height floor on the top edge | The preferred content size's height is greater than `136` and matches the pane's own measured height within `0.5` pt |
| tab-pane-010 | card-width-is-bounded; card-height-has-a-floor-and-grows-with-content | Content short enough to floor width and height on every edge (the slack that differs by edge is masked once content is at the floor) | All four edges report the same floored preferred content size |
| tab-pane-011 | selection-and-depth-are-reconciled | Pane never highlighted; stack depth never explicitly set | The agent label's role is the behind role before any highlight |
| tab-pane-012 | selection-and-depth-are-reconciled | Set highlighted to true | The agent label's role becomes the front (accent) role |
| tab-pane-013 | front-and-behind-cards-use-distinct-backgrounds | Card not highlighted vs. highlighted | The reported fill/border colors equal the window-background/border roles when behind, and the workspace-backdrop/outline roles when front |
| tab-pane-014 | front-card-overhangs-the-workspace-edge; behind-card-recedes-from-the-workspace-edge | Card highlighted vs. not, on every edge | The reported workspace overhang equals the workspace overlap (`1`) when front, and `-4` when behind at depth `1` on every edge |
| tab-pane-015 | behind-card-recedes-from-the-workspace-edge | Highlighted card vs. a card at depth `1` | The behind card's painted frame is inset `4` pt on every side and is smaller than the front card's frame on both axes |
| tab-pane-016 | vertical-edge-recession-accumulates-with-depth | Depths 1, 2, 3 on left/right edges | Recession is `4`, `8`, `12` pt respectively |
| tab-pane-017 | horizontal-edge-recession-is-constant | Depths 1, 2, 3 on top/bottom edges | Recession is `4` pt at every one of those depths |
| tab-pane-018 | paint-and-text-move-together | Card moved to a receded depth | The card's text frame moves in by the same inset as its painted frame |
| tab-pane-019 | front-card-overhangs-the-workspace-edge | Card at depth 0 | The card's text frame stays inside its bounds while its painted frame extends past those bounds on the workspace side |
| tab-pane-020 | depth-change-is-immediate-when-detached | Card not attached to a window; set depth to `2` | The card is not animating and its reported workspace overhang reflects the new depth immediately, with no animation |
| tab-pane-021 | depth-change-animates-when-attached-to-a-window | Card attached to a window; change depth | The card is animating and its set of in-progress move animations is non-empty during the transition |
| tab-pane-022 | selection-and-depth-are-reconciled | Highlighted state toggled true → false → true with varying stack-depth values, including `0` | The reported workspace overhang never reads as "front" while not highlighted, whatever depth was last reported |
| tab-pane-023 | front-and-behind-cards-differ-in-role-and-color | Card constructed (behind, depth ≥ 1) vs. highlighted (front) | The agent label's role is the behind role when behind and the front role when highlighted; the session/directory/branch labels never fall below the dimmer-but-readable behind roles from the front/behind role table at any depth |
| tab-pane-024 | close-button-callback | Close callback set; close button clicked | The callback fires exactly once |
| tab-pane-025 | context-menu-is-delegated | Delegate set, returns a specific menu for a given event | Requesting a context menu returns that exact menu, and the delegate is asked exactly once |
| tab-pane-026 | close-button-sits-on-the-outward-end | Pane constructed on each of the four edges | On the left edge, the close button is the header's first element; on top/right/bottom, it is the last |
| tab-pane-027 | subviews-carry-tab-scoped-accessibility-identifiers | Pane constructed with a known tab ID | The root view and each labeled subview expose `tab-pane.<part>.<tabID>` |
| tab-pane-028 | session-text | The data source returns session name `"tabs"`; reload | The session label reads `"tabs"` |
| tab-pane-029 | title-and-preferred-content-size | The data source returns session name `"tabs"`; reload | The title reads `"tabs"` (matching the session label) and the preferred content size equals the card's content size |
| tab-pane-030 | nil-data-source | No data source is set; reload | The view is loaded but no label, title, or preferred content size is touched |
| tab-pane-031 | redundant-depth-set-is-a-no-op | Card attached to a window; set stack depth to its own current value | The set of in-progress move animations stays empty and the reported workspace overhang is unchanged, because a redundant set never re-runs the depth-change logic |
| tab-pane-032 | recession-does-not-increase-past-depth-three | Vertical edge; depth set past the maximum stack depth (`4` beyond it) | The reported workspace overhang equals the value at the maximum depth, not any larger |
| tab-pane-033 | labels-do-not-intercept-clicks | Card constructed on any edge | None of the agent, session, directory, branch, or summary labels are selectable |
| tab-pane-034 | status-glyph-has-an-accessible-label | Replace the status glyphs with one symbol whose accessibility label is `"Busy"` | The resulting glyph's accessibility label reads `"Busy"`, independent of its symbol name |
| tab-pane-035 | component-does-not-poll-its-data-source | The data source's answers change after construction, with no reload call | No label, title, or preferred content size changes on its own; content changes only appear after an explicit reload |
| tab-pane-036 | directory-text | The data source returns a working directory outside the current user's home, e.g. `/tmp/repo/.claude/worktrees/tabs`; reload | The directory label reads that path unabbreviated |
| tab-pane-037 | context-menu-is-delegated | Delegate is nil (or set but returns nil for the event); a menu-triggering event fires | Requesting a context menu falls back to the platform's standard context menu |
| tab-pane-038 | header-text; session-text; branch-visibility; summary-visibility; title-and-preferred-content-size | Reload once with short content (agent `"C"`, no model, session `"s"`, branch `"b"`, no summary), then again after every field changes and grows past the maximum width | The agent, session, and branch labels follow the new values; the summary label becomes shown once a summary appears; the preferred content size's width moves from the minimum to the maximum between the two calls |

## Edge Cases

- **Null/empty input - model absent**: The model name is nil → the agent
  label MUST show the agent name alone, with no separator.
- **Null/empty input - branch/summary absent**: The branch/summary are nil →
  the corresponding label MUST be hidden rather than shown empty.
- **Null/empty input - data source absent**: No data source is set when
  reload is called → the component MUST take no action beyond ensuring the
  view is loaded, leaving whatever was last displayed unchanged. This is
  the source's only handling of a missing dependency; no error, placeholder,
  or logged diagnostic is produced.
- **Boundary values - depth at the recession ceiling**: Stack depth at `3`
  (the maximum) or any larger value MUST recede the card by the same amount
  as depth `3` - recession does not keep growing past that ceiling.
- **Boundary values - content far below/above the card's natural size**:
  Content shorter than the minimum width/height MUST still measure at the
  floor; content wider than the maximum width MUST clamp at the cap rather
  than overflow.
- **Redundant state change**: Setting the stack depth to its own current
  value MUST be a no-op - no animation starts and the depth-change logic is
  not re-run.
- **Concurrent access**: Not applicable in the general sense - every
  property and method that touches display state runs on a single
  execution context, so there is no multi-threaded mutation path to defend
  against. See Platform Notes.
- **Error states - dependency unavailable**: The only external dependency is
  the data source; its absence is handled as described above (no-op), not
  as a surfaced error. There is no network, database, or file-system
  dependency in this component to fail.
- **Offline/disconnected state**: Not applicable - the component performs no
  networking of its own; all content arrives synchronously from data-source
  calls.
- **Repeated reload with changing values**: Calling reload twice with a data
  source that has changed its answers between calls MUST update every
  label, the title, and the preferred content size to the new values on the
  second call, including newly appearing/disappearing branch or summary
  text.
- **View never attached to a window**: A depth change on a pane whose view
  has never been added to a window's view hierarchy MUST apply immediately
  with no animation, since there is nothing on screen to animate and an
  animated constraint would read a stale value if measured right after.
- **Edge-dependent measurement slack (documented quirk, not a guaranteed
  invariant)**: The content size's slack term (twice the deepest recession)
  is edge-dependent - `24` pt on a vertical edge (`3` steps × `4` pt × `2`)
  versus `8` pt on a horizontal edge (`1` step × `4` pt × `2`) - so, in
  principle, the same content could measure a different preferred content
  size depending solely on which edge hosts the pane. The deepest-recession
  calculation reuses the same recession formula used elsewhere, whose body
  answers a different question for a vertical edge (how far the deepest of
  several stacked cards recedes) than for a horizontal edge (a constant
  single-step recession) - the two questions happen to share one
  implementation. Every existing call site and test happens to mask this:
  short content is floored to the minimum and long content is capped at the
  maximum, regardless of which slack value applied (see tab-pane-010), so
  the difference has never been observed to change a real layout, but the
  formula itself is not edge-independent when content sits strictly between
  the floor and the cap.

## Configuration

Not applicable: the pane exposes no tunable, per-instance configuration
options. The edge and tab ID (set once at construction) are fixed identity,
not configuration a caller varies for behavior or appearance; every other
number that shapes the card (minimum/maximum width, minimum height,
workspace overlap, per-step recession inset, maximum stack depth, animation
duration, padding) is a compiled-in constant, never exposed as an
initializer parameter or settable property.

## Deep Linking

Not applicable: the component is an embedded tab-bar item shown inside the
tabbed view, not an independently addressable destination - no URL scheme,
universal link, or route table is referenced anywhere in this component.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none - hardcoded literal, no localization lookup) | `Close` | The close button's icon's accessibility label. |

All other visible text - agent name, model name, session name, working
directory, branch, and summary - is opaque data supplied by the data
source, not UI copy authored by this component; localizing that content, if
ever needed, is the data source's responsibility, not this component's.

The `Close` description has no localization lookup, so the screen reader
reads it in English only, regardless of the user's locale. See Platform
Notes for why this string in particular is not itself a localization key on
the source platform.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not implemented in source. The depth-driven recession/overhang move animates whenever the card's view has a window, with no check of the system's Reduce Motion setting anywhere in this component. Because this is a positional/size animation - a slide of the card's paint and text inset, not an opacity-only cross-fade - it falls outside the fade exemption, and the move animates unconditionally whenever the view has a window, regardless of the Reduce Motion setting. |
| Increase Contrast | Not applicable: the component draws only theme-resolved semantic colors (`.primaryText`, `.secondaryText`, `.tertiaryText`, `.accent`, `.border`, `.windowBackground`, `.projectPaneBackdrop`, `.projectPaneOutline`) obtained from the resolved theme's palette; any Increase Contrast adaptation of those values is the palette resolver's responsibility, not a branch this component takes itself. |
| Differentiate Without Color | Supported. A card behind the front one is not distinguished by color alone: it is also drawn measurably smaller and pulled back from the workspace edge, so size and position remain as independent, non-color cues to which card is selected. |

## Feature Flags

Not applicable: no feature-flag or remote-config lookup appears anywhere in
this component; the component is unconditionally present wherever it is
instantiated.

## Analytics

Not applicable: no analytics or telemetry event is emitted anywhere in this
component.

## Privacy

- **Data collected**: None of its own. The component displays agent name,
  model name, session name, working directory, branch, and summary that the
  data source supplies; it never gathers, derives, or forwards data beyond
  what it is handed to render.
- **Storage**: None - displayed values live only as in-memory state for as
  long as the view controller exists; nothing is written to disk or
  persisted settings.
- **Transmission**: None - the component performs no networking; it never
  sends any of the data it displays anywhere.
- **Retention**: None beyond the pane's own lifetime - display state is
  replaced wholesale on the next reload and discarded when the view
  controller is deallocated.

## Logging

Not applicable: no logging call appears anywhere in this component.

## Platform Notes

- **SwiftUI**: Model each pane as a small view value exposing
  agent/model/session/directory/branch/summary/status plus `isFront: Bool`
  and `depth: Int`. Render the header as an `HStack` (agent `Text`, status
  `HStack` of small `Image(systemName:)`, `Spacer()`, close `Button`),
  reversing element order for the left edge with a conditional array rather
  than a mirrored layout direction, since only the close button's position
  changes, not the whole reading order. Drive fill/border/text color from
  `isFront` via `.foregroundStyle`/`.background`, and express recession as
  `.padding(edgeSet, CGFloat(min(depth, 3)) * 4)` on a vertical edge or a
  flat `4` on a horizontal one, wrapped in `withAnimation(.easeOut(duration:
  0.16))` gated on whether the view is already inserted into the hierarchy
  (mirroring the animates-when-attached check - an unattached view should
  set its position with no animation transaction at all). There is no
  direct SwiftUI equivalent of the one-point workspace overhang; approximate
  it with a `.padding(edge, -1)` applied to the card's background shape
  alone, not the whole view, so the overhang does not also push the text.
- **Compose**: Represent the pane as a `@Composable` taking the same data
  plus `isFront`/`depth` state. Build the header as a `Row` with
  `Arrangement.SpaceBetween`, reversing only the close button's position for
  a left-edge-equivalent layout with a conditional element order, not a
  mirrored `LayoutDirection.Rtl`, since only the close button's position
  changes, not the whole reading order. Animate recession with
  `animateDpAsState(targetValue = ..., animationSpec = tween(160, easing =
  LinearOutSlowInEasing))` applied to a `Modifier.padding` or
  `Modifier.offset`, mirroring the ease-out timing curve. Because Compose's
  `border` modifier always strokes all four sides, reproduce the open-sided
  outline with a custom `Modifier.drawWithContent` that strokes only the
  three non-workspace-facing sides via a hand-built `Path`, exactly as the
  card's own path-tracing skips the fourth side.
- **React/Web**: Render the card as a `<div>` with CSS custom properties for
  background/border color toggled by a `data-front` attribute, and a header
  using `display: flex; justify-content: space-between`, reversing only the
  close button's position for a left-edge-equivalent layout with a
  conditional DOM order, not `flex-direction: row-reverse` on the whole
  header, since only the close button's position changes, not the whole
  reading order. Animate the recession with a `transition: inset 160ms
  cubic-bezier(0, 0, 0.58, 1)` (ease-out) on `inset`/`transform:
  translate(...)`, applied only once the element is mounted (a freshly
  mounted card sets its initial inset with no transition class, mirroring
  the no-animation-when-detached case). Reproduce the three-sided open
  outline with individual `border-top`/`border-right`/`border-bottom`/
  `border-left` declarations instead of the `border` shorthand, omitting the
  workspace-facing side.
- **AppKit / UIKit** (source platform): Source lives in
  `TabPaneViewController.swift` (controller: identity, data-source-driven
  `reload()`, `TabBarStackedItem` conformance, `applyDepth()` reconciling
  selection with depth) and `TabPaneView.swift` (the visual card: geometry
  constants, `CardSides`/`InsetBox` inset math, `TabCardBackgroundView`'s
  open-path fill/stroke, and the `NSAnimationContext`-driven move). This is
  AppKit/macOS-only; no UIKit code path exists. `TabPaneViewController`
  cannot be instantiated from a storyboard or XIB - `init?(coder:)` returns
  `nil` (formerly the normative requirement
  `view-controller-does-not-support-storyboard-instantiation`) - and every
  property and method that reads or mutates the pane's displayed state is
  confined to a `@MainActor` declaration, enforced at compile time by
  Swift's isolation checking (formerly the normative requirement
  `component-is-main-actor-confined`; this is the source of the Concurrent
  Access edge case above). The close button's accessibility description is
  a plain `String` passed to `accessibilityDescription`; unlike SwiftUI's
  `Text`/`Label`, whose literal argument is a `LocalizedStringKey`, a plain
  `String` parameter is not itself a localization key, so this string is
  genuinely unlocalized (see Localization above). A UIKit port would replace
  `NSBezierPath`/`draw(_:)` with `UIBezierPath`/`CAShapeLayer`, and would
  drive the recession move through `UIView.animate` or an explicit
  `CABasicAnimation` on the constraint's owning view, since UIKit has no
  `NSAnimationContext`/`allowsImplicitAnimation` equivalent for constraint
  changes.
- **WinUI 3**: Build the card as a `UserControl` whose visual is a
  `Microsoft.UI.Xaml.Shapes.Path` with a hand-built `PathGeometry`/
  `PathFigure` running through the same three corner points the card's own
  corner calculation computes - a XAML `Border` always strokes all four
  sides and cannot leave the workspace-facing side open, so it cannot
  express this shape directly. Bind the path's `Fill`/`Stroke` brushes to
  "Front"/"Behind" resource keys switched through a `VisualStateManager`
  state group. Animate the recession/overhang move with a `Storyboard`
  containing a `DoubleAnimation` (`Duration="0:0:0.16"`, `EasingFunction` a
  `QuadraticEase` with `EasingMode="EaseOut"`, mirroring the ease-out timing
  curve) targeting a `TranslateTransform` or `Margin`, gated on whether the
  control is currently in the visual tree - an unloaded control should call
  `Storyboard.SkipToFill()` to jump rather than animate, mirroring the
  animates-when-attached check. Lay out the header in a `Grid` with the
  close `Button` placed via `Grid.Column`/`HorizontalAlignment` depending on
  edge, its `Width`/`Height` fixed at `14` (not `Padding`) to match the
  fixed hit area, and size each status glyph's `FontIcon` at `11`px to
  mirror the icon's point size. Bind `AutomationProperties.AutomationId` to
  `"tab-pane." + tabId` (and `.agent.`/`.session.`/`.directory.`/`.branch.`/
  `.summary.`/`.close.` per sub-control) through a converter, matching the
  accessibility-identifier scheme.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/TabPane/TabPaneViewController.swift` |

## Design Decisions

**Decision**: An unhighlighted card's drawn depth is clamped to at least `1`
(`max(1, stackDepth)`) rather than trusting `stackDepth` directly, including
its own default value of `0`.
**Rationale**: Per `applyDepth()`'s own doc comment, the `max` "is what keeps
[selection and depth] from contradicting each other: a card that is not the
selected one is never the card in front, whatever depth it was last told -
including the initial zero, before any bar has said anything," because the
hosting bar communicates selection and depth as two independent signals that
can arrive in either order.
**Approved**: pending

**Decision**: A card with no window takes a new depth immediately and
without animation, while a card in a window animates the move.
**Rationale**: Per `animatesDepthChanges`'s doc comment, "a card with no
window is not on screen: there is nothing to watch move, and an animated
constraint reads its old value until the animation ends," so measuring an
off-screen card immediately after a depth change would read a stale,
mid-animation value instead of the settled one.
**Approved**: pending

**Decision**: On a horizontal edge every card behind the front one recedes by
exactly one step, while on a vertical edge the recession accumulates per
depth up to the maximum stack depth.
**Rationale**: Per `recession(atDepth:)`'s doc comment, a horizontal bar
"lays its cards out along their long side" with no column to fan them down,
so there is nothing for a deeper card to recede further into, whereas a
vertical bar's cards overlap down a column and can visually "fan away" like
a deck.
**Approved**: pending

**Decision**: The card's open-sided background stroke insets its three drawn
sides by `0.5` pt but gives the workspace-facing side its half-point back
while the card is in front.
**Rationale**: Per `strokeBounds()`'s doc comment, a `1` pt line otherwise
straddles the view's own edge; while the front card's paint reaches out over
the workspace's outline, "the fill and the two side strokes have to run all
the way out through the overhang," or a visible seam would appear where the
two surfaces are meant to read as one.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | partial | Accessibility |
| [reduced-motion](agenticdevelopercookbook://compliance/accessibility#reduced-motion) | failed | Accessibility |
| [touch-target-size](agenticdevelopercookbook://compliance/accessibility#touch-target-size) | failed | Accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | Internationalization |

`screen-reader-support` and `keyboard-navigable` are `partial` because the card has no focus behavior or accessibility role of its own, no combined accessibility label across its fields, and the close button's `accessibilityDescription` is an unlocalized literal (see **close-button-callback** and the Localization section above); `reduced-motion` and `touch-target-size` are `failed` on the confirmed absence of a Reduce Motion check and a fixed `14`pt close-button hit area below the 44pt minimum; `string-externalization` is `failed` on the hardcoded `Close` literal.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed requirements to subject-only names, merged the duplicate selection/depth requirements, added an explicit per-label role/color table, fixed frontmatter references and moved the misplaced cookbook link to `related`, added missing test vectors and corrected several test-vector-to-requirement mappings, moved the edge-dependent measurement quirk from Design Decisions to Edge Cases, reformatted Design Decisions to the bold three-line form, deleted leftover template instructions, corrected Platform Notes for Compose/React header reordering and Compose's easing curve, and marked two Compliance checks `partial` with a supporting sentence |
| 1.1.1 | 2026-09-23 | Mike Fullerton | Compliance: removed rows for checks absent from the cookbook catalog, remapped reduce-motion-support to reduced-motion |
| 1.1.2 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.3 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/layout/tabbed-view/. |
