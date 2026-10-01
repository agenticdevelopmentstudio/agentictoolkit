---
id: d906afe1-a621-42f1-87c5-c71ec9d43c1e
title: Tab Pane View
domain: agentictoolkit://cookbook/ui/layout/tabbed-view/tab-card-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A card view for one tab in a tabbed-view edge bar that sizes, colors,
  and animates between front and stacked-behind depths.
platforms:
- swift
- macos
tags:
- tabs
- tab-bar
- card
- layout
depends-on: []
related:
- agentictoolkit://cookbook/ui/layout/tabbed-view
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references:
- https://developer.apple.com/design/human-interface-guidelines/
approved-by: ''
approved-date: ''
---

# Tab Pane View

## Overview

The component is a card drawn as one tab in an edge bar of
[the tabbed view](agentictoolkit://cookbook/ui/layout/tabbed-view): a stacked
block, the same arrangement on all four edges, showing a session's
agent/model name, status symbols, session name, working directory, branch,
and an optional summary. It is hosted by a controller that drives its stack
depth and highlighted state through a stacked-item interface. The card in
front (depth `0`) paints what the workspace paints, in the workspace's own
outline color, and overhangs the bar by one point to cover the line the
workspace draws down that side, so one unbroken line runs around the active
card and the workspace it belongs to. A card behind stops short of its own
edge instead, leaving the workspace's line whole, and — on a vertical
(left/right) edge only — recedes further with every step of depth, so a
column of cards reads as a deck turned to the selected tab.

## Behavioral Requirements

- **accessibility-ids-assigned-per-instance**: On construction, the component
  MUST assign a distinct accessibility identifier to itself (`tab-pane.<uuid>`)
  and to the agent label, session label, directory label, branch label,
  summary label, and close control (each `tab-pane.<field>.<uuid>`), using
  the tab ID passed to it, so two tabs never share an identifier.
- **labels-truncate-by-middle-default**: The agent label, session label, and
  branch label MUST truncate overflowing text in their middle (the other two
  text labels start there too, before **directory-label-truncates-head** and
  **summary-label-truncates-tail** override them).
- **labels-resist-compression-at-low-priority**: The agent, session,
  directory, branch, and summary labels MUST each be given the lowest
  priority for resisting horizontal compression, so they are the first
  elements to shrink when space is limited.
- **directory-label-truncates-head**: The directory label MUST override its
  truncation to occur at the head (start) of the text.
- **summary-label-truncates-tail**: The summary label MUST override its
  truncation to occur at the tail (end) of the text.
- **labels-not-selectable**: All five text labels MUST NOT be selectable, so
  a pointer-down on a label's own area is not consumed by beginning a text
  selection and instead reaches whatever hosts this card's tab-selection
  handling.
- **summary-label-hidden-by-default**: The summary label MUST start hidden
  when the view is set up.
- **close-button-configuration**: The close control MUST display a close
  ("x" in a circle) icon only, with no border or bezel, in a fixed `14×14pt`
  frame.
- **close-action-forwards-to-onclose**: Component MUST invoke the close
  callback, and nothing else, when the close control's action fires.
- **header-close-button-placement**: The header MUST place the close control
  at its leading end when the card is on the left edge and at its trailing
  end for every other edge.
- **header-gap-absorbs-extra-width**: The invisible spacer between the
  agent/status group and the close control MUST be the element that absorbs
  any extra width in the header, rather than the agent label or the status
  row stretching.
- **content-padding**: The content column's edge insets MUST equal `top: 12,
  left: 14, bottom: 12, right: 14`.
- **content-stack-order**: The content column's arranged elements MUST be, in
  order: the header, the session label, the directory label, the branch
  label, the summary label, and a trailing spacer.
- **header-width-matches-content**: Component MUST constrain the header's
  width equal to the content column's width minus `26pt` (the sum of the
  content column's own left and right edge insets).
- **spacer-absorbs-extra-height**: The trailing spacer in the content column
  MUST be the element that absorbs any extra height the card has beyond what
  its content needs, rather than the five text lines growing.
- **self-not-pinned-either-axis**: Component MUST NOT constrain its own width
  or height to a fixed or computed value; both axes are left to the hosting
  bar (cross axis) and to the host's own preferred-size mechanism (length
  axis).
- **content-size-floors**: The card's content size MUST be no narrower than
  `240pt` (a minimum width), no wider than `340pt` (a maximum width), and no
  shorter than `136pt` (a minimum height), regardless of the content's own
  measured size.
- **content-size-grows-with-recession-slack**: The card's content size MUST
  add `2 × deepestRecession` (twice the recession at the maximum stack depth)
  to the content's natural width and height before applying the floors
  above.
- **front-card-defined-by-zero-depth**: The card MUST be considered the front
  card if and only if its stack depth is `0`.
- **depth-change-applies-only-on-change**: Setting the stack depth to its
  current value MUST NOT re-run the depth-change logic; only an actual
  change of value MUST trigger it.
- **depth-recession-flat-on-horizontal-edge**: On a top or bottom edge, the
  recession at any depth greater than zero MUST be exactly `4pt`, however
  large that depth is.
- **depth-recession-accumulates-on-vertical-edge**: On a left or right edge,
  the recession MUST grow `4pt` per step of depth: `4pt` at depth `1`, `8pt`
  at depth `2`, `12pt` at depth `3`.
- **depth-recession-clamps-past-max-stack-depth**: On a left or right edge,
  the recession MUST be the same `12pt` for any depth of `3` or greater.
- **front-card-overhangs-workspace**: When the card is the front card, its
  painted background MUST extend `1pt` (the workspace overlap) past the
  card's own bounds on the side facing the workspace.
- **text-stays-inset-on-workspace-side**: The card's text column MUST remain
  inset by the recession on the workspace-facing side even while the card is
  the front card and its painted background overhangs that side.
- **front-card-palette**: When the card is the front card, its background
  fill MUST use the resolved theme's `projectPaneBackdrop` color and its
  border MUST use `projectPaneOutline`.
- **behind-card-palette**: When the card is not the front card, its
  background fill MUST use the `windowBackground` role and its border MUST
  use the `border` role.
- **front-card-agent-label-role**: The agent label's role MUST be `.accent`
  when the card is the front card and `.primaryText` when it is not.
- **front-card-session-label-role**: The session label's role MUST be
  `.primaryText` when the card is the front card and `.secondaryText` when
  it is not.
- **front-card-secondary-label-roles**: The directory, branch, and summary
  labels' roles MUST each be `.secondaryText` when the card is the front
  card and `.tertiaryText` when it is not.
- **close-button-tint-follows-depth**: The close control's tint MUST be the
  `.secondaryText` role color when the card is the front card and the
  `.tertiaryText` role color when it is not.
- **theme-change-repaints-card**: Component MUST recompute its appearance
  whenever the active theme changes, so the card's colors track the palette
  live.
- **animated-only-when-in-window**: Depth-change animation MUST be enabled
  only while the card is on screen (attached to a window).
- **depth-animation-duration-and-curve**: An animated depth change MUST run
  over `0.16s` using an ease-out timing curve.
- **depth-animation-settles-pending-layout-first**: Before starting an
  animated depth change, component MUST force any outstanding layout to
  complete before opening the animation, so the animation does not start
  from a stale, pre-layout frame.
- **context-menu-delegates-to-provider**: Requesting a context menu MUST
  return the context-menu provider's menu when a provider is set and returns
  non-nil, and MUST fall back to the platform's default context menu
  otherwise.
- **status-symbols-replace-existing**: Replacing the status symbols MUST
  remove every previously added status icon from the status row before
  adding the icons for the new symbol list.
- **status-symbol-view-configuration**: Each status symbol's icon MUST render
  at `11pt`, regular weight, in a fixed `14×14pt` frame, and MUST carry the
  symbol's accessibility label as its own accessibility label.
- **status-symbol-missing-image-fallback**: Replacing the status symbols MUST
  substitute an empty placeholder image when a symbol name fails to resolve
  to an icon, rather than crashing or leaving a nil image.
- **zero-size-card-draws-nothing**: The card's background painting MUST draw
  nothing when its stroke bounds have zero or negative width or height.
- **card-path-omits-workspace-side**: The card's painted fill and stroke MUST
  trace only the three sides other than the one facing the workspace; the
  workspace-facing side MUST remain visually open, with no stroke drawn along
  it.
- **stroke-inset-by-half-point**: The card's three stroked sides MUST be
  inset `0.5pt` from the view's bounds, so the `1pt` stroke lands fully
  inside the card.
- **reaches-over-workspace-restores-half-point**: When the card reaches over
  the workspace, the workspace-facing side of the stroke bounds MUST be
  extended back out by that same `0.5pt`, so the fill and the two side
  strokes run flush through the overhang with no seam against the
  workspace's own line.
- **card-fill-and-border-color-accessors**: The card's reported fill and
  border colors MUST always report exactly the colors currently painted on
  the card's background.
- **workspace-overhang-accessor**: The card's reported workspace overhang
  MUST report `0` before layout has run and MUST otherwise report the card's
  current overhang.
- **running-move-animations-accessor** (formerly `animation-keys-accessor`):
  The card's set of in-progress move animations MUST report the union of the
  move animations currently running on its background and its content
  column.
- **onclose-is-optional**: Component MAY be left with no close callback set;
  a press of the close control then has no observable effect beyond calling
  nothing.
- **context-menu-provider-is-optional**: Component MAY be left with no
  context-menu provider set, in which case requesting a context menu always
  falls back to the platform's default context menu.

## Appearance

- **Corner radius**: Not applicable — the card's outline traces straight
  line segments only; no rounded-rect or arc is used anywhere, so every
  corner is square.
- **Padding**: The content column's edge insets: `top: 12, left: 14, bottom:
  12, right: 14`. The content column's spacing: `6pt` between arranged
  elements. The status row's spacing: `2pt` between status symbols. The
  header's own spacing: `6pt` between the agent label, status row, gap, and
  close control.
- **Font**: The agent label and session label use the `body` text role (base
  `13pt`, regular weight — scales with the active theme's size scale). The
  directory label, branch label, and summary label use the `caption` text
  role (base `11pt`, regular weight, same scaling).
- **Background**: Front card: the resolved palette's `projectPaneBackdrop`
  color. Behind card: the `windowBackground` role.
- **Foreground/Text**: Front card: the agent label in `.accent`; the session
  label in `.primaryText`; the directory/branch/summary labels in
  `.secondaryText`; the close control's tint in `.secondaryText`. Behind
  card: the agent label in `.primaryText`; the session label in
  `.secondaryText`; the remaining three labels and the close control's tint
  in `.tertiaryText`.
- **Border**: `1pt` stroke in `projectPaneOutline` (front) or `border`
  (behind), traced along three sides only — the side facing the workspace is
  left open.
- **Shadow**: Not applicable — the card only fills and strokes its outline;
  no shadow is drawn anywhere.
- **Min/Max size**: Card width: `240pt`–`340pt`. Card height: `≥ 136pt`,
  unbounded above. The close control and each status icon: fixed `14×14pt`
  frame. Status symbol glyphs render at `11pt`, regular weight; the close
  control's glyph renders at the platform's default control-image size
  within its `14×14pt` frame.

## States

| State | Appearance change |
|-------|------------------|
| Default (depth `1`, before any caller sets it) | Behind — same as the "Behind, horizontal edge" or "Behind, vertical edge" row below, whichever edge this card is on. |
| Front (depth `0`) | Background = `projectPaneBackdrop`, border = `projectPaneOutline`, agent label = `.accent`, session label = `.primaryText`, the other three labels and the close tint = `.secondaryText`; painted background overhangs the workspace-facing side by `1pt`; text inset at depth `0` is `0` — only the paint overhangs. |
| Behind, horizontal edge (depth > 0, top/bottom) | Background = `windowBackground`, border = `border`, agent label = `.primaryText`, the rest and the close tint = `.tertiaryText`; card and text pulled in `4pt` on every side, flat regardless of depth. |
| Behind, vertical edge (depth 1–3, left/right) | Same palette as "Behind" above; card and text pulled in `4pt` per step of depth, up to `12pt` at depth `3` and beyond, so deeper cards read visibly smaller and further back. |
| Depth transition (card on screen) | The recolor/reposition above animates over `0.16s` with an ease-out curve rather than jumping; off-screen it jumps. |
| Pressed | Not applicable: the component defines no mouse-tracking behavior and no pressed appearance; a click is the hosting item's concern (documented in the tabbed-view recipe), not this component's. |
| Disabled | Not applicable: no disabled state, tint, or appearance is defined anywhere; a tab card that exists is always drawn at full strength. |
| Focused | Not applicable: no custom focus-ring or focused appearance is defined; the close control's focus indicator is left at the platform default, and no other element declares itself keyboard-focusable. |
| Loading | Not applicable: every operation in this component (updating status symbols, content updates, depth changes) is synchronous; no loading/pending indicator is defined. |

## Accessibility

- **Role/trait**: The component sets an accessibility identifier on itself
  and on each subview (for automated-test addressing) but sets no
  accessibility role and does not mark itself as a single accessibility
  element grouping its children (unlike the tab button used elsewhere in the
  tabbed view, which does group its children). The screen reader reads the
  card as five separate, individually-focused text elements in sequence,
  with no indication that they describe one tab.
- **Label requirements**: The close control's icon carries an accessibility
  label of "Close" (see Localization). Each status icon carries the
  caller-supplied accessibility label for its symbol. The agent, session,
  directory, branch, and summary labels receive no explicit accessibility
  label in this component; the screen reader falls back to each label's own
  displayed text, the platform's default for a plain text label.
- **Announce state changes**: Recomputing appearance recolors and
  repositions the card whenever it becomes or stops being the front card,
  but the component posts no accessibility notification when that happens; a
  screen reader user tracking a different element is not told this card's
  selection state changed when no click of their own caused it.
- **Minimum tap target**: The close control's hit area is a fixed `14×14pt`.
  This is a pointer-driven desktop context; the `44×44pt` (mobile) /
  `48×48dp` (Android) touch-target minimums do not apply directly here and
  instead inform the touch-platform translations in Platform Notes.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| tab-pane-001 | accessibility-ids-assigned-per-instance | Construct the card for a given edge and tab ID | The card's own accessibility identifier is `tab-pane.<id>`; the agent label's is `tab-pane.agent.<id>` (and likewise for the other four fields and the close control) |
| tab-pane-002 | labels-truncate-by-middle-default | Construct the card | The agent, session, and branch labels all truncate overflowing text in the middle |
| tab-pane-003 | labels-resist-compression-at-low-priority | Construct the card | The agent label is the first to shrink under horizontal space pressure, at the lowest resistance priority |
| tab-pane-004 | directory-label-truncates-head | Construct the card | The directory label truncates overflowing text at its head |
| tab-pane-005 | summary-label-truncates-tail | Construct the card | The summary label truncates overflowing text at its tail |
| tab-pane-006 | labels-not-selectable | Construct the card | None of the five text labels are selectable |
| tab-pane-007 | summary-label-hidden-by-default | Construct the card, before any content is set | The summary label starts hidden |
| tab-pane-008 | close-button-configuration | Construct the card | The close control has no border or bezel, shows only its icon, and its hit area is `14×14`pt |
| tab-pane-009 | close-action-forwards-to-onclose | Set a close callback; simulate a press of the close control | The callback fires |
| tab-pane-010 | header-close-button-placement | Construct the card for the left edge vs. any other edge | On the left edge the header places the close control first; on every other edge it places it last |
| tab-pane-011 | header-gap-absorbs-extra-width | Widen the header beyond its content's natural width | The gap between the agent/status group and the close control grows; the agent label and status row do not stretch |
| tab-pane-012 | content-padding | Inspect the content column's edge insets | `top == 12`, `left == 14`, `bottom == 12`, `right == 14` |
| tab-pane-013 | content-stack-order | Inspect the content column's arranged elements | Order is header, session label, directory label, branch label, summary label, spacer |
| tab-pane-014 | header-width-matches-content | Lay out the card | The header's width equals the content column's width minus `26`pt |
| tab-pane-015 | spacer-absorbs-extra-height | Give the card more height than its text needs | The trailing spacer in the content column grows; the five text lines stay at the top |
| tab-pane-016 | self-not-pinned-either-axis | Inspect the card's own constraints | No required-priority constraint pins the card's width or height directly |
| tab-pane-017 | content-size-floors | All labels empty, no status symbols, on the top edge | Content size is `240×136`pt |
| tab-pane-018 | content-size-grows-with-recession-slack | Compare content size on the top edge vs. the left edge, with identical content sized to land clear of both size floors and ceilings on either edge | The left edge's content size is exactly `2 × 12 = 24pt` larger than the top edge's, on both width and height |
| tab-pane-019 | front-card-defined-by-zero-depth | Set depth to `0`, then to `1` | The card reads as front, then as not front (verified indirectly via its reported fill color) |
| tab-pane-020 | depth-change-applies-only-on-change | Record the card's fill color, border color, and running move animations, then set depth to its current value | All three are unchanged afterward: no new animation appears and the colors match the values recorded before the redundant set |
| tab-pane-021 | depth-recession-flat-on-horizontal-edge | Top edge; set depth to `1`, then `5` | Recession is `4pt` in both cases |
| tab-pane-022 | depth-recession-accumulates-on-vertical-edge | Left edge; set depth to `1`, `2`, `3` | Recession is `4pt`, `8pt`, `12pt` respectively |
| tab-pane-023 | depth-recession-clamps-past-max-stack-depth | Left edge; set depth to `3`, then `10` | Recession is `12pt` in both cases |
| tab-pane-024 | front-card-overhangs-workspace | Top edge; set depth to `0` | The card's reported workspace overhang is `1` |
| tab-pane-025 | text-stays-inset-on-workspace-side | Top edge; set depth to `0` | The text column's workspace-facing edge stays at the card's slot boundary, while the painted background's workspace-facing edge extends past it |
| tab-pane-026 | front-card-palette | Set depth to `0` | The reported fill color matches the workspace-backdrop role; the reported border color matches the workspace-outline role |
| tab-pane-027 | behind-card-palette | Set depth to `1` | The reported fill color matches the window-background role; the reported border color matches the border role |
| tab-pane-028 | front-card-agent-label-role | Toggle depth between `0` and `1` | The agent label's role toggles between accent and primary text |
| tab-pane-029 | front-card-session-label-role | Toggle depth between `0` and `1` | The session label's role toggles between primary text and secondary text |
| tab-pane-030 | front-card-secondary-label-roles | Toggle depth between `0` and `1` | The directory, branch, and summary labels' roles each toggle between secondary text and tertiary text |
| tab-pane-031 | close-button-tint-follows-depth | Toggle depth between `0` and `1` | The close control's tint toggles between the secondary-text and tertiary-text role colors |
| tab-pane-032 | theme-change-repaints-card | Change the active theme | The card's reported fill and border colors update to the new theme's values with no other call |
| tab-pane-033 | animated-only-when-in-window | Change depth on a card not attached to a window, then on one attached to a window | No move animation appears in the first case; one appears (mid-transition) in the second |
| tab-pane-034 | depth-animation-duration-and-curve | Change depth on a card attached to a window | The running animation's duration is `0.16` and its timing curve is ease-out |
| tab-pane-035 | depth-animation-settles-pending-layout-first | Resize the card without letting a pending layout settle, then change depth on a card attached to a window | The running animation's starting frame equals the frame the pending layout would have produced, not the frame from before the resize — no stale frame is animated from |
| tab-pane-036 | context-menu-delegates-to-provider | Set a context-menu provider that returns a given menu; request a context menu | Returns that exact menu |
| tab-pane-037 | context-menu-delegates-to-provider | Leave the context-menu provider returning nothing; request a context menu | Returns the platform's default context menu |
| tab-pane-038 | status-symbols-replace-existing | Replace the status symbols with two, then with one | Only one status icon remains after the second call, with no leftover icons from the first |
| tab-pane-039 | status-symbol-view-configuration | Replace the status symbols with one idle symbol | The added icon's frame is `14×14`; it renders at `11`pt; its accessibility label reads "Idle" |
| tab-pane-040 | status-symbol-missing-image-fallback | Replace the status symbols with one whose icon name does not resolve | No crash; the resulting icon is a non-nil empty image |
| tab-pane-041 | zero-size-card-draws-nothing | Force the card's background painting to zero-size bounds; trigger a redraw | No fill or stroke operation is issued (no crash, no drawn path) |
| tab-pane-042 | card-path-omits-workspace-side | Top-edge card; inspect the drawn outline | The path touches only the left, top, and right sides; the bottom (workspace) side has no segment between its two corner points |
| tab-pane-043 | stroke-inset-by-half-point | Top-edge card, not reaching over the workspace | The stroke bounds are inset `0.5pt` from the card's bounds on every side |
| tab-pane-044 | reaches-over-workspace-restores-half-point | Top-edge card, reaching over the workspace | The stroke bounds' workspace-facing edge is extended back out by `0.5pt` relative to the non-overhanging case |
| tab-pane-045 | card-fill-and-border-color-accessors | Set the card's painted fill color to a given color | The card's reported fill color matches it |
| tab-pane-046 | workspace-overhang-accessor | Query the card's reported workspace overhang before layout has run | Returns `0` |
| tab-pane-047 | running-move-animations-accessor | Mid-way through an animated depth change | The card's set of in-progress move animations is non-empty |
| tab-pane-048 | onclose-is-optional | Leave the close callback unset; press the close control | No crash; no observable side effect |
| tab-pane-049 | context-menu-provider-is-optional | Leave the context-menu provider unset; request a context menu | Returns the platform's default context menu |
| tab-pane-050 | status-symbols-replace-existing | On a freshly constructed card with no prior status symbols, replace the status symbols with none | No status icons remain |

## Edge Cases

- Null/empty input (MUST): Replacing the status symbols with none MUST leave
  the status row with no icons. The card's content size MUST still return at
  least `240×136pt` even when every label's text is empty and no status
  symbols are set, because of the unconditional floor/ceiling in the content
  size calculation.
- Boundary values (documented behavior, not a gap): Stack depth accepts any
  integer with no lower or upper clamp. The recession calculation treats any
  depth `≤ 0` as zero recession, while front-card status requires depth `==
  0` exactly — so a negative depth draws the non-front palette (window
  background/border/tertiary text) at zero inset and zero overhang, a
  combination no depth of `0` or greater produces. See Design Decisions. On
  a vertical edge, any depth of `3` or more MUST produce the same `12pt`
  recession.
- Concurrent access: Not applicable — the component confines all of its
  mutable state and methods to a single execution context, so there is no
  path for two threads to mutate one instance at the same time. See Platform
  Notes.
- Error states (MUST): Replacing the status symbols MUST substitute an empty
  placeholder image when a symbol name fails to resolve to an icon, rather
  than crashing. The card's background painting MUST draw nothing when its
  stroke bounds have zero or negative width or height, rather than
  constructing a degenerate path.
- Offline/disconnected: Not applicable — this component performs no
  networking of any kind; every value it displays is handed to it
  in-process by its controller's reload operation.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Stack depth | Integer | `1` | How far back in the stack this card is drawn; `0` means the front (selected) card. |
| Close callback | Optional callback, no input or output | `nil` | Called when the close control's action fires. |
| Context-menu provider | Optional callback taking the triggering input event and returning an optional menu | `nil` | Supplies the menu returned when a context menu is requested; falls back to the platform's default context menu when `nil` or when it returns `nil`. |

Replacing the status symbols takes a list of status-symbol values: a small,
immutable, thread-safe pairing of an icon name with an accessibility label.
Source defines one built-in value, Idle (accessibility label "Idle" — the
value tab-pane-039 exercises); callers may construct other values directly.
See Platform Notes for the concrete icon identifiers.

## Deep Linking

Not applicable: the component defines no URL scheme, system-activity object,
route, or deep-link handler; the card is constructed and updated only by
direct, in-process calls from its controller.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — | "Close" | The close control's icon's accessibility label |

"Close" is a hardcoded English string literal passed directly as the
accessibility label, not routed through any localization mechanism used in
this component. (The status symbols' accessibility labels, and every label's
displayed text, are caller-supplied data from the data source and
status-symbol values — like a tab's own title in the tabbed-view recipe,
they carry no localization concern of this component's own making.)

## Accessibility Options

- **Reduce Motion**: The depth-change animation slides and resizes the
  card's paint and text boxes (a position *and* size change, not a plain
  opacity cross-fade) over `0.16s` whenever depth changes while the card is
  on screen; nothing in this component checks the system's Reduce Motion
  setting before running that animation, so a Reduce Motion user sees the
  same slide as anyone else.
- **Increase Contrast**: Not applicable — every color this component draws
  (`projectPaneBackdrop`, `projectPaneOutline`, `windowBackground`, `border`,
  `.accent`, `.primaryText`, `.secondaryText`, `.tertiaryText`) is a semantic
  palette role; Increase Contrast handling, if any, belongs to the
  theme/palette system this component defers to, not to this file.
- **Differentiate Without Color**: Supported. The front/behind distinction
  is never carried by color alone: a behind card is also drawn smaller and
  further from the workspace (recession, `≥ 4pt` on every side) and never
  overhangs the workspace's outline, while the front card does both — a
  geometry-based cue that accompanies every color change the appearance
  update makes.

## Feature Flags

Not applicable: no feature-flag or config-gating lookup appears anywhere in
this component; the card behaves identically regardless of any external
flag.

## Analytics

Not applicable: this component contains no analytics or telemetry call.

## Privacy

- **Data collected**: None by this component itself. It renders
  caller-supplied display strings (agent/model name, session name,
  working-directory path, branch name, summary) and caller-supplied status
  symbols; it does not capture, log, or forward any of it elsewhere.
- **Storage**: In-memory only, for the life of the view. Nothing in this
  component persists to disk.
- **Transmission**: Not applicable — no networking call appears anywhere in
  this component.
- **Retention**: None beyond the view's own lifetime.

## Logging

Not applicable: this component contains no logging call.

## Platform Notes

- **SwiftUI**: Model the open-sided outline as a custom `Shape` (a
  `path(in:)` implementation tracing the same four points
  `TabCardBackgroundView.corners(of:)` does, per edge, and never closing back
  across the workspace-facing side), composed as a `.background`/`.overlay`
  pair (fill, then stroke) behind a `VStack` mirroring the content column's
  order (header `HStack`, then the four remaining labels, then a `Spacer()`
  in place of the trailing spacer). Drive front/recession/overhang from a
  passed-in `depth: Int`, and wrap the shape's frame/offset change in
  `.animation(.easeOut(duration: 0.16), value: depth)` — gated behind
  `@Environment(\.accessibilityReduceMotion)` per the Reduce Motion gap noted
  above. Use `.lineLimit(1)` with `.truncationMode(.middle)`/`.head`/`.tail`
  to match the per-label truncation modes.
- **Compose**: Draw the same open-sided outline with a `Canvas`/`Path` in a
  `Box`, sized by a `Modifier.widthIn(min = 240.dp, max = 340.dp)` /
  `heightIn(min = 136.dp)`. Represent front/behind with an `animateDpAsState`
  (or `animateFloatAsState`) driving inset/offset over `160.milliseconds`
  with an `EaseOut` easing curve, checked against the system animator
  duration scale (`Settings.Global.ANIMATOR_DURATION_SCALE`, read via
  `ContentResolver` — a scale of zero means Reduce Motion is on;
  `LocalAccessibilityManager` does not expose this setting) before animating.
  Lay out the header as a `Row` with a `Spacer(Modifier.weight(1f))`
  in place of the gap, and the remaining lines in a `Column`, each using
  `TextOverflow.StartEllipsis`, `TextOverflow.MiddleEllipsis`, or
  `TextOverflow.Ellipsis` to match the per-label head/middle/tail truncation
  mode (`Modifier.basicMarquee()` scrolls text rather than truncating it, so
  it does not apply here).
- **React/Web**: Build the card as a `<div>` whose background fills the
  full rect but whose border is set on only three sides (the CSS
  longhands `border-top`/`border-left`/`border-right`, omitting the
  workspace-facing side) — or, for the exact open-path stroke, an inline SVG
  `<path>` built from the same four points. Transition `margin`/`transform`
  over `0.16s ease-out` for the depth change, gated behind a
  `prefers-reduced-motion: reduce` media query per the Reduce Motion gap
  above. Use CSS `text-overflow: ellipsis` for tail truncation, `direction:
  rtl` on an inner span for head truncation (the directory-label case), and
  a `<button aria-label="Close">` for the close control.
- **AppKit/UIKit** (source platform): Implemented in
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/TabPane/TabPaneView.swift`
  (`TabPaneView`, plus the file-private `InsetBox`, `CardSides`, and
  `TabCardBackgroundView` types), hosted by `TabPaneViewController.swift` in
  the same directory. This is a macOS-only, AppKit `NSView` component with no
  UIKit code path in source. The type is `final` and confines its mutable
  state via a `@MainActor` declaration — construction and mutation are
  restricted to the main actor, enforced at compile time by Swift's isolation
  checking (this is the source of the Concurrent Access edge case above).
  `init?(coder:)` is `@available(*, unavailable)` and returns `nil`, so the
  type cannot be constructed from a storyboard or XIB (formerly the
  normative requirement `init-from-coder-unavailable`); `self`, the
  background box, and the content stack all set `wantsLayer = true` during
  setup, so all three are layer-backed for coloring and animation (formerly
  the normative requirement `wants-layer-on-self-and-boxes`). Icons are SF
  Symbols: the close control uses `xmark.circle.fill` with `imagePosition =
  .imageOnly`, no bezel (`isBordered = false`, `bezelStyle = .inline`); the
  one built-in status symbol, `.idle`, uses `moon.zzz`; a status icon whose
  name fails to resolve falls back to an empty `NSImage()`. Depth-change
  animation uses a `CAMediaTimingFunction(name: .easeOut)` and reports its
  progress via the running `CALayer` animation keys on the background and
  content boxes (this is the source of the `running-move-animations-accessor`
  requirement above). A UIKit port has no first-class analog to an
  `NSBezierPath`-drawn, three-sided open card that overhangs a sibling view
  by a point; it would use a plain `UIView` with a `CAShapeLayer` (a
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
  `EasingFunction` matching ease-out, e.g. `CubicEase EasingMode="EaseOut"`),
  skipped in favor of an immediate `Margin` set when
  `Windows.UI.ViewManagement.UISettings.AnimationsEnabled` (or the app's own
  Reduce Motion setting) is off — mirroring the Reduce Motion gap noted
  above, which this port should not repeat. Swap `Background`/`Foreground`
  `SolidColorBrush`es between the front and behind palettes with a
  `VisualStateManager` `FrontCard`/`BehindCard` state group, the way the
  appearance-update logic swaps palette roles. Lay out the header as a
  `Grid` with `Auto,Auto,*,Auto` columns (agent label, status stack, gap,
  close button) — a horizontal `StackPanel` cannot host a star-sized column,
  so the third column's `*` sizing takes the place of the gap, absorbing the
  header's extra width — followed by a close `Button` in the fourth column,
  styled borderless (`Style="{StaticResource TransparentButtonStyle}"` or
  equivalent), sized `14x14`, using the Segoe Fluent Icons `&#xE711;`
  ("Cancel") glyph, with `AutomationProperties.Name="Close"`. Represent the
  status symbols as a horizontal `ItemsRepeater`/`StackPanel` of `14x14`
  `FontIcon`s, each with its own `AutomationProperties.Name` bound to the
  caller-supplied label. Bind `MinWidth`/`MinHeight` growth to the hosted
  content's measured `DesiredSize` plus the recession slack, mirroring the
  content size calculation.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/TabPane/TabPaneView.swift` |

## Design Decisions

- Decision (AppKit): `init?(coder:)` is `@available(*, unavailable)` and its
  body returns `nil` rather than calling `fatalError()`.
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
- Decision (AppKit): The card's own view is left unpinned on both axes — no
  self-constraint on width or height.
  Rationale: Per `setUp()`'s inline comment, the cross axis is the hosting
  bar's own required-priority constraint (`TabBarView.rebuildButtons()`) and
  the length axis is AppKit's own priority-501
  `NSViewController.preferredContentSize` constraint, driven by
  `contentSize`; a required self-pin here would restate one of those two
  numbers at required priority and risk an unsatisfiable conflict with
  whichever one wins.
  Approved: pending
- Decision (AppKit): `contentSize` measures `content.fittingSize`, not the
  card's own `fittingSize`.
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
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | partial | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | accessibility |
| [reduced-motion](agenticdevelopercookbook://compliance/accessibility#reduced-motion) | failed | accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | internationalization |

Keyboard-navigable is partial
because `closeButton` is a real `NSButton` and gets standard key-view-loop
operability for free, but selecting the card itself has no keyboard path in
this file — that is the hosting `TabItemHostView`'s concern (see the
`multi-tabbed-view-controller` recipe's own `keyboard-navigable: failed`
finding). Screen-reader-support is partial because accessibility identifiers
and status-symbol labels are set explicitly, but the card sets no
`accessibilityRole` and groups nothing for VoiceOver (see Accessibility).
Reduced-motion is failed for the gap documented in Accessibility Options.
String-externalization is failed because `closeButton`'s "Close" accessibility
description is a hardcoded English literal (see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: reworded the truncation-default requirement to name only its three non-overridden labels; fixed the Default and Front state descriptions; restated two internal-call test vectors as observable outcomes and the recession-slack vector to clear the size clamp; added missing test vectors for a nil context-menu provider and empty status symbols; corrected the WinUI 3 header layout and close-glyph and the Compose truncation/Reduce-Motion notes; documented `TabPaneStatusSymbol` in Configuration; moved a cookbook cross-reference from `references` to `related`; trimmed one tag over the 1-5 limit; and removed the two accessibility compliance rows that used a disallowed `not-applicable` status. |
| 1.1.1 | 2026-09-23 | Mike Fullerton | Compliance: removed rows for checks absent from the cookbook catalog, remapped reduce-motion-support to reduced-motion |
| 1.1.2 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.3 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/layout/tabbed-view/. |
