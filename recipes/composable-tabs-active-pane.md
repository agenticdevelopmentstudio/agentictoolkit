---
id: 08bfb299-851b-4b01-a84a-6a2a13e07c12
title: ComposableTabsActivePane
domain: agentictoolkit://recipes/composable-tabs-active-pane
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Per-window tracker of which composable-tabs pane the user is working in,
  plus the pane backdrop view that draws its outline.
platforms:
- swift
- macos
tags:
- composable-tabs
- active-pane
- focus
- appkit
- macos
depends-on: []
related: []
references:
- https://developer.apple.com/design/human-interface-guidelines/
approved-by: ''
approved-date: ''
---

# ComposableTabsActivePane

## Overview

`ComposableTabsActivePane` (`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsActivePane.swift`)
is a `@MainActor` singleton that tracks, independently for each open `NSWindow`,
which composable-tabs pane the user is currently working in — the one they
last clicked in, or, with the `activePaneFollowsMouse` user setting on, the one
under the pointer. AppKit has no "the first responder changed" notification
and a pane's own content swallows mouse events before a pane could see them
itself, so the tracker installs one local `NSEvent` monitor for the whole app
(`leftMouseDown`, `rightMouseDown`, `mouseMoved`) instead of every pane
installing a monitor of its own, and answers "which pane is this point in"
with one hit test rather than a second implementation of it living in a
tracking area.

The same file also defines `ComposableTabsPaneBackgroundView`, an `NSView`
that is a pane's backdrop and draws the "this is the pane you are working in"
border. It is one view — not an overlay — so the border can never end up
under the pane's own content, and it registers its arrival and departure with
`ComposableTabsActivePane` as it moves in and out of a window, and repaints
whenever the tracker, the window's key state, or the highlight setting
changes.

Neither type renders or exposes anything else: no title, no icon, no
interactive control of its own. The chrome a pane wears beyond this backdrop
(title bar, gear menu, content identifier) belongs to
`ComposableTabsPaneViewController` and its own sources, not to this file, and
is out of scope for this recipe.

## Behavioral Requirements

- **tracks-active-node-per-window**: The component MUST maintain, independently
  for each `NSWindow`, at most one active pane node id at a time.
- **unclaimed-pane-counts-as-active**: `isInActivePane(_:)` MUST return `true`
  for a view inside a `ComposableTabsPaneBackgroundView` whose window has no
  active node id recorded yet.
- **membership-decided-by-node-id-match**: `isInActivePane(_:)` MUST return
  `true` for a view inside a `ComposableTabsPaneBackgroundView` only when that
  background's `nodeID` equals the window's recorded active node id (or the
  window has none recorded, per **unclaimed-pane-counts-as-active**), and
  MUST return `false` otherwise.
- **view-outside-any-pane-counts-as-active**: `isInActivePane(_:)` MUST return
  `true` for a view that has no `ComposableTabsPaneBackgroundView` anywhere in
  its superview chain.
- **nil-window-has-no-active-node**: `activeNodeID(in:)` MUST return `nil`
  when passed a `nil` window.
- **arrival-claims-active-in-an-unclaimed-window**: `paneDidAppear(_:in:)`
  MUST activate the arriving pane when no live pane already on screen in that
  window holds the active id.
- **arrival-does-not-steal-active-from-a-live-pane**: `paneDidAppear(_:in:)`
  MUST NOT change the window's active id when a live pane already on screen
  in that window holds it.
- **arrival-enables-mouse-moved-tracking-when-setting-on**:
  `paneDidAppear(_:in:)` MUST set the window's `acceptsMouseMovedEvents` to
  `true` whenever `activePaneFollowsMouse` is enabled, regardless of whether
  the arriving pane becomes the active one.
- **departure-hands-off-to-a-surviving-pane**: `paneDidDisappear(_:from:)`
  MUST reassign the window's active id to another live pane in the same
  window when the departing pane held the active id and at least one other
  live pane remains.
- **departure-clears-active-id-when-no-pane-survives**:
  `paneDidDisappear(_:from:)` MUST remove the window's active-id entry
  entirely when the departing pane held the active id and no other live pane
  remains in that window.
- **departure-of-a-non-active-pane-is-inert**: `paneDidDisappear(_:from:)`
  MUST NOT alter the window's active id, and MUST NOT post
  `didChangeNotification`, when the departing pane did not hold the active id.
- **window-close-clears-active-id-silently**: The component MUST remove a
  window's active-id entry when that `NSWindow` posts `willCloseNotification`,
  and MUST NOT post `didChangeNotification` when doing so.
- **activation-is-idempotent**: `activate(nodeID:in:)` MUST have no effect,
  and MUST NOT post `didChangeNotification`, when `nodeID` already equals the
  window's current active id.
- **activation-posts-notification-on-change**: `activate(nodeID:in:)` MUST
  post `didChangeNotification`, with the window as its object, whenever it
  changes the window's active id.
- **setting-enabled-reaches-already-open-windows**: Turning
  `activePaneFollowsMouse` on MUST enable `acceptsMouseMovedEvents` on every
  window the component is already tracking, not only on windows opened after
  the change.
- **accepts-mouse-moved-is-never-reset-to-false**: The component MUST NOT
  reset a window's `acceptsMouseMovedEvents` back to `false` when
  `activePaneFollowsMouse` is or becomes disabled; disabling the setting only
  stops `mouseMoved` events from being acted on, not received.
- **clicks-are-evaluated-regardless-of-the-setting**: The event monitor MUST
  evaluate every `leftMouseDown` and `rightMouseDown` event regardless of the
  `activePaneFollowsMouse` setting.
- **mouse-moved-is-gated-by-the-setting**: A `mouseMoved` event MUST be
  ignored unless `activePaneFollowsMouse` is enabled.
- **mouse-moved-is-gated-by-key-window**: A `mouseMoved` event MUST be
  ignored when its window is not the key window.
- **mouse-moved-is-gated-by-an-attached-sheet**: A `mouseMoved` event MUST be
  ignored when its window has an attached sheet.
- **mouse-moved-is-gated-by-arrange-mode**: A `mouseMoved` event MUST be
  ignored when `ComposableTabsArrangeMode` is enabled for that window.
- **event-outside-any-pane-is-ignored**: An event whose hit-tested point does
  not land inside any `ComposableTabsPaneBackgroundView` MUST be ignored.
- **event-on-the-already-active-pane-is-a-no-op**: An event, click or move,
  that hit-tests to the pane already holding the window's active id MUST
  cause no state change.
- **click-activates-a-different-pane-directly**: A `leftMouseDown` or
  `rightMouseDown` that hit-tests to a pane other than the currently active
  one MUST activate that pane.
- **mouse-moved-takes-focus-before-activating**: A `mouseMoved` event that
  hit-tests to a pane other than the currently active one MUST attempt to
  move keyboard focus into that pane before the pane is activated.
- **focus-refusal-blocks-mouse-moved-activation**: When the outgoing first
  responder refuses to resign during the focus attempt a `mouseMoved` event
  triggers, the hit-tested pane MUST NOT be activated.
- **the-event-monitor-never-consumes-an-event**: The local event monitor MUST
  return every event it observes unmodified.
- **focus-walk-proceeds-innermost-to-outermost**: `takeFocus(within:in:)`
  MUST offer first-responder status to the hit-tested chain of views in
  innermost-to-outermost order, stopping at the first view that accepts it.
- **focus-walk-treats-the-current-responder-as-already-taken**:
  `takeFocus(within:in:)` MUST treat a candidate view that is already the
  window's first responder as taken, without calling `makeFirstResponder`
  again for it.
- **focus-walk-stops-on-outgoing-refusal**: `takeFocus(within:in:)` MUST stop
  the walk and report a refusal the moment a `makeFirstResponder` attempt
  leaves the outgoing first responder still in place.
- **focus-walk-restores-the-original-responder-on-exhaustion**: When no
  candidate in the chain accepts first-responder status, `takeFocus(within:in:)`
  MUST attempt to restore the original first responder and, if that succeeds,
  MUST report that there was nowhere to put the keys.
- **focus-walk-reports-refused-when-restoration-fails**: When no candidate
  accepts first-responder status and the attempt to restore the original
  first responder fails, `takeFocus(within:in:)` MUST report a refusal.
- **every-pane-is-always-outlined**: `applyTheme(_:)` MUST draw a 2-point
  border on every `ComposableTabsPaneBackgroundView`, whether or not it is the
  active pane.
- **the-backdrop-is-always-the-pane-backdrop-color**: `applyTheme(_:)` MUST
  set the view's layer background color to `palette.projectPaneBackdrop`
  regardless of active state.
- **the-active-pane-uses-the-accent-outline-color**: `applyTheme(_:)` MUST
  color the border with `palette.projectActivePaneOutline` when, and only
  when, the pane holds its window's active id, the window is focused, and the
  effective highlight setting is enabled.
- **every-other-pane-uses-the-hairline-outline-color**: `applyTheme(_:)` MUST
  color the border with `palette.projectPaneOutline` in every case that does
  not satisfy **the-active-pane-uses-the-accent-outline-color**.
- **the-accent-color-requires-a-focused-window**: `applyTheme(_:)` MUST NOT
  use the accent border color when the pane's window is neither key nor has a
  key attached sheet, even when the pane holds that window's active id.
- **an-attached-sheet-counts-the-window-as-focused**: `applyTheme(_:)` MUST
  treat the pane's window as focused when that window's attached sheet is the
  key window, even when the window itself is not key.
- **a-theme-override-takes-precedence-over-the-user-setting**: `applyTheme(_:)`
  MUST use the current theme's `project.highlightActivePane` override when the
  theme sets one, and MUST fall back to `UserSettings.highlightActivePane`
  only when the theme does not.
- **the-fill-is-inset-from-the-backdrop-edges**: The pane's fill subview MUST
  be constrained on all four edges to `ComposableTabsPaneBackgroundView.borderInset`
  (2 points) inside the backdrop's own bounds.
- **the-fill-is-the-first-subview**: The fill subview MUST be added to the
  backdrop before any other subview, so chrome added later renders above it.
- **a-window-change-reports-departure-before-arrival**: `viewDidMoveToWindow()`
  MUST report the backdrop's departure from its previous window, when it had
  one and it differs from the new one, before reporting its arrival in the
  new window.
- **the-backdrop-repaints-on-its-own-windows-activation-change**: The backdrop
  MUST reapply its theme when `didChangeNotification` is posted with its own
  window as the object, and MUST ignore that notification for any other
  window.
- **the-backdrop-repaints-on-any-key-window-change**: The backdrop MUST
  reapply its theme whenever any window becomes or resigns key, not only its
  own.
- **the-backdrop-repaints-on-a-highlight-setting-change**: The backdrop MUST
  reapply its theme when `UserSettings` publishes a change to
  `highlightActivePane`.

## Appearance

- **Corner radius**: None. The backdrop is a plain rectangular `NSView` layer
  with no `cornerRadius` set.
- **Padding**: Not applicable in the padding sense; the backdrop's fill
  subview is inset from the backdrop's own edges by `borderInset` (2pt) on
  all four sides, leaving that band for the border to draw in.
- **Font**: Not applicable. The component draws no text.
- **Background**: `palette.projectPaneBackdrop` (a theme-overridable role,
  falling back to a semantic surface role defined outside this file) on the
  backdrop's layer; the fill subview inside it is a `ThemedBackgroundView`
  painted with the `.windowBackground` role.
- **Foreground/Text**: Not applicable. The component draws no text or icon.
- **Border**: 2 points wide on every pane, always. Color is
  `palette.projectActivePaneOutline` for the active pane in a focused window
  with highlighting enabled, and `palette.projectPaneOutline` otherwise.
- **Shadow**: None. The source sets no shadow on the backdrop's layer.
- **Min/Max size**: None imposed by this file. The backdrop is sized by its
  pane's own layout (auto-layout constraints applied by the surrounding pane
  view controller, not by this file).

## States

| State | Appearance change |
|-------|--------------------|
| No pane has claimed the window yet | No pane's backdrop draws the accent color; every pane reads as "inactive" (hairline outline) until the first `paneDidAppear` claims the spot. |
| Active pane, window focused, highlighting enabled | 2pt border in `projectActivePaneOutline`; backdrop in `projectPaneBackdrop`. |
| Active pane, window not focused (not key and no key attached sheet) | 2pt border in `projectPaneOutline`, same as an inactive pane. |
| Active pane, highlighting disabled (by user setting or theme override) | 2pt border in `projectPaneOutline`, same as an inactive pane. |
| Inactive pane | 2pt border in `projectPaneOutline`; backdrop in `projectPaneBackdrop`. |
| Arrange mode enabled in the window | Pointer movement no longer changes the active pane; clicks still do. |
| Window has an attached sheet | Pointer movement no longer changes the active pane in that window; the sheet itself has the keys. |

## Accessibility

- **Role/traits**: Not applicable. `ComposableTabsPaneBackgroundView` sets no
  `accessibilityRole`, `accessibilityLabel`, or `accessibilityElement` value
  of its own anywhere in the source — it is a backdrop, not a control. Any
  role or label a pane's actual content needs belongs to that content's own
  view controller, which is out of scope for this file (see Overview).
- **Keyboard/assistive-technology navigation**: This is the file's central
  accessibility-relevant behavior. Every pointer-driven pane switch (gated by
  `activePaneFollowsMouse`) is paired with an ordinary `NSResponder`
  first-responder change, using the same `makeFirstResponder` mechanism a
  click already uses (see **mouse-moved-takes-focus-before-activating**,
  **focus-walk-proceeds-innermost-to-outermost**, and
  **focus-refusal-blocks-mouse-moved-activation**). Because focus moves
  through the standard responder chain rather than a private mechanism,
  VoiceOver's own focus-follows-first-responder behavior applies without
  anything further from this file; the component defines no separate
  accessibility-notification call of its own (no
  `NSAccessibility.post(element:notification:)` appears anywhere in the
  source), and none is required, because the underlying focus change is
  already the standard, observable one.
- **Minimum tap target**: Not applicable. `ComposableTabsPaneBackgroundView`
  is a full-bleed backdrop sized by its enclosing pane's own layout; it is
  not a discrete tappable control with an independently sized hit target, and
  the source treats it as neither a button nor a control.
- **Contrast**: NEEDS REVIEW: `palette.projectPaneBackdrop`,
  `palette.projectPaneOutline`, and `palette.projectActivePaneOutline` are
  theme-overridable roles — their actual color values are chosen per theme
  (see the Theme Editor's Project topic, `ThemeProjectTopicPanel`), not fixed
  in this source file, so the contrast between the active border and its
  adjacent backdrop cannot be computed from `ComposableTabsActivePane.swift`
  alone, and depends on which theme is active. Resolvable only by whoever
  audits each shipped theme's actual token values against a numeric contrast
  threshold (e.g. WCAG 1.4.11 non-text contrast, 3:1) for this
  border-against-backdrop pairing; this file has no mechanism to enforce a
  minimum contrast on an arbitrary theme.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| CTA-01 | tracks-active-node-per-window | Two windows, each with panes activated independently | Each window's active id is independent of the other's |
| CTA-02 | unclaimed-pane-counts-as-active | A pane's backdrop in a window with no recorded active id | `isInActivePane` returns `true` for a view inside that backdrop |
| CTA-03 | membership-decided-by-node-id-match | Two panes in one window, one active | `isInActivePane` returns `true` for a view inside the active pane's backdrop and `false` for a view inside the other |
| CTA-04 | view-outside-any-pane-counts-as-active | A view with no `ComposableTabsPaneBackgroundView` ancestor (e.g. a standalone panel) | `isInActivePane` returns `true` |
| CTA-05 | nil-window-has-no-active-node | Call `activeNodeID(in: nil)` | Returns `nil` |
| CTA-06 | arrival-claims-active-in-an-unclaimed-window | `paneDidAppear` for the first pane in a fresh window | That pane becomes the active one |
| CTA-07 | arrival-does-not-steal-active-from-a-live-pane | A window already has an active pane; a second pane's `paneDidAppear` fires | The active id is unchanged |
| CTA-08 | arrival-enables-mouse-moved-tracking-when-setting-on | `activePaneFollowsMouse` enabled; a second (non-claiming) pane appears | `window.acceptsMouseMovedEvents` is `true` |
| CTA-09 | departure-hands-off-to-a-surviving-pane | Active pane's `paneDidDisappear` fires while a sibling pane remains in the window | The sibling becomes the new active pane |
| CTA-10 | departure-clears-active-id-when-no-pane-survives | Active pane's `paneDidDisappear` fires and it was the window's only pane | `activeNodeID(in:)` returns `nil` afterward |
| CTA-11 | departure-of-a-non-active-pane-is-inert | A non-active pane's `paneDidDisappear` fires | Active id is unchanged; `didChangeNotification` is not posted |
| CTA-12 | window-close-clears-active-id-silently | The window posts `willCloseNotification` | `activeNodeID(in:)` returns `nil` for that window afterward; no `didChangeNotification` is observed |
| CTA-13 | activation-is-idempotent | Call `activate(nodeID:in:)` with the id already active | No state change; no notification posted |
| CTA-14 | activation-posts-notification-on-change | Call `activate(nodeID:in:)` with a different id | `didChangeNotification` posted with that window as its object |
| CTA-15 | setting-enabled-reaches-already-open-windows | Two windows already tracked, then `activePaneFollowsMouse` is turned on | Both windows' `acceptsMouseMovedEvents` become `true` |
| CTA-16 | accepts-mouse-moved-is-never-reset-to-false | `activePaneFollowsMouse` turned on then off again | `window.acceptsMouseMovedEvents` remains `true` |
| CTA-17 | clicks-are-evaluated-regardless-of-the-setting | `activePaneFollowsMouse` disabled; a `leftMouseDown` lands on a different pane | That pane is activated |
| CTA-18 | mouse-moved-is-gated-by-the-setting | `activePaneFollowsMouse` disabled; pointer moves to a different pane | Active pane is unchanged |
| CTA-19 | mouse-moved-is-gated-by-key-window | `activePaneFollowsMouse` enabled; pointer moves over a non-key window's pane | Active pane is unchanged |
| CTA-20 | mouse-moved-is-gated-by-an-attached-sheet | Window has an attached sheet; pointer moves over one of its panes | Active pane is unchanged |
| CTA-21 | mouse-moved-is-gated-by-arrange-mode | Arrange mode enabled in the window; pointer moves over a different pane | Active pane is unchanged |
| CTA-22 | event-outside-any-pane-is-ignored | A click lands outside every pane's backdrop | No state change |
| CTA-23 | event-on-the-already-active-pane-is-a-no-op | A click or pointer move lands on the already-active pane | No state change; no notification posted |
| CTA-24 | click-activates-a-different-pane-directly | `leftMouseDown` lands on a non-active pane | That pane becomes active |
| CTA-25 | mouse-moved-takes-focus-before-activating | `activePaneFollowsMouse` enabled; pointer moves onto a non-active pane containing a focusable view | Focus moves to the innermost focusable view before the pane is activated |
| CTA-26 | focus-refusal-blocks-mouse-moved-activation | Outgoing responder refuses `resignFirstResponder`; pointer moves onto a non-active pane | Active pane is unchanged; first responder is unchanged |
| CTA-27 | the-event-monitor-never-consumes-an-event | Any monitored event | The event is still delivered to the responder chain afterward |
| CTA-28 | focus-walk-proceeds-innermost-to-outermost | A pane whose innermost hit-tested view refuses focus but an outer one accepts | The outer, focus-accepting view becomes first responder |
| CTA-29 | focus-walk-treats-the-current-responder-as-already-taken | The innermost hit-tested view is already first responder | `takeFocus` reports success without calling `makeFirstResponder` again |
| CTA-30 | focus-walk-stops-on-outgoing-refusal | The current first responder refuses to resign | `takeFocus` reports refusal; the walk does not continue to further candidates |
| CTA-31 | focus-walk-restores-the-original-responder-on-exhaustion | No candidate in the chain accepts focus, and the window's first responder ends up on the window itself along the way | The original first responder is restored; `takeFocus` reports "nowhere to put" |
| CTA-32 | focus-walk-reports-refused-when-restoration-fails | No candidate accepts focus and restoring the original first responder fails | `takeFocus` reports refusal |
| CTA-33 | every-pane-is-always-outlined | Any pane, active or not | `layer.borderWidth` is `2` |
| CTA-34 | the-backdrop-is-always-the-pane-backdrop-color | Any pane, active or not | `layer.backgroundColor` equals `palette.projectPaneBackdrop` |
| CTA-35 | the-active-pane-uses-the-accent-outline-color | Pane is active, its window is key, highlighting enabled | `layer.borderColor` equals `palette.projectActivePaneOutline` |
| CTA-36 | every-other-pane-uses-the-hairline-outline-color | Pane is inactive (or active but window unfocused, or highlighting disabled) | `layer.borderColor` equals `palette.projectPaneOutline` |
| CTA-37 | the-accent-color-requires-a-focused-window | Pane is active but its window is not key and has no key attached sheet | `layer.borderColor` equals `palette.projectPaneOutline`, not the accent |
| CTA-38 | an-attached-sheet-counts-the-window-as-focused | Window is not key but its attached sheet is key; pane is active | `layer.borderColor` equals `palette.projectActivePaneOutline` |
| CTA-39 | a-theme-override-takes-precedence-over-the-user-setting | Theme's `project.highlightActivePane` set to `false`, `UserSettings.highlightActivePane` set to `true` | The pane is drawn as not highlighted |
| CTA-40 | the-fill-is-inset-from-the-backdrop-edges | Backdrop laid out at a known frame | The fill subview's frame equals the backdrop's bounds inset by 2pt on every edge |
| CTA-41 | the-fill-is-the-first-subview | Backdrop after `init` | The fill is `subviews[0]` |
| CTA-42 | a-window-change-reports-departure-before-arrival | A backdrop is moved from window A to window B | Window A's `paneDidDisappear` handling completes before window B's `paneDidAppear` handling begins |
| CTA-43 | the-backdrop-repaints-on-its-own-windows-activation-change | `didChangeNotification` posted for the backdrop's own window | `applyTheme` is invoked; posting it for a different window does not invoke it |
| CTA-44 | the-backdrop-repaints-on-any-key-window-change | Any window becomes or resigns key | `applyTheme` is invoked on every tracked backdrop, including ones in other windows |
| CTA-45 | the-backdrop-repaints-on-a-highlight-setting-change | `UserSettings` publishes a change to `highlightActivePane` | `applyTheme` is invoked |

## Edge Cases

- Null/empty input: `activeNodeID(in: nil)` MUST return `nil` rather than
  trapping or treating a missing window as any particular window's state.
- Null/empty input: An `NSEvent` with no associated `window` MUST be ignored
  by `record(_:)` — traced to `guard let window = event.window else { return }`.
- Null/empty input: A window whose `contentView` is `nil` MUST be treated as
  having no pane under any point — traced to `paneChain(under:in:)`'s
  `guard let contentView = window.contentView else { return nil }`.
- Boundary values: A window with zero panes MUST have no entry in the active
  id map, and any view queried against that window (there being no pane to
  contain it) counts as active per **view-outside-any-pane-counts-as-active**.
- Boundary values: A window with exactly one pane MUST have that pane hold
  the active id once it appears, per **arrival-claims-active-in-an-unclaimed-window**,
  and MUST have no active pane left once it departs, per
  **departure-clears-active-id-when-no-pane-survives**.
- Concurrent access: The whole component is `@MainActor`; every mutation of
  its window/pane bookkeeping happens on the main actor, so concurrent access
  from multiple threads is not a case this file has to handle. Two sources
  that could otherwise race with in-flight AppKit event tracking —
  `NSWindow.willCloseNotification` and the `highlightActivePane` settings
  publisher — are explicitly re-dispatched onto `DispatchQueue.main` (not
  `RunLoop.main`) so a change made while AppKit tracks a mouse-down in
  `.eventTracking` run-loop mode is still applied, rather than being deferred
  until the tracking loop ends.
- Error states: The only "failure" outcome in this file is a view refusing
  first-responder status (`makeFirstResponder` returning `false`). This MUST
  be handled internally by `takeFocus(within:in:)`'s three-way
  `FocusOutcome` (`taken` / `nowhereToPut` / `refused`) as described above; it
  is never surfaced to a caller, logged, or shown to the user — there is no
  user-visible error state for a focus refusal beyond the outline and
  keyboard simply not moving.
- Offline/disconnected: Not applicable. The component makes no network call
  and has no server-backed state; it is a pure in-memory, single-process
  tracker of per-window UI state.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|--------------|
| `UserSettings.activePaneFollowsMouse` | `UserSetting<Bool>` | `false` | Whether pointer movement, not just clicks, can change the active pane and hand it the keyboard. |
| `UserSettings.highlightActivePane` | `UserSetting<Bool>` | `true` | Whether the active pane's border is drawn in the accent color at all, unless overridden per theme. |
| Theme's `project.highlightActivePane` | `Bool?` (per-theme override) | `nil` (falls through to `UserSettings.highlightActivePane`) | A theme's own override of the same highlight toggle, edited in the Theme Editor's Project topic. |
| `ComposableTabsPaneBackgroundView.borderInset` | `CGFloat` (public static constant) | `2` | How far the pane's own fill is held off the backdrop's edge, in points, leaving room for the border. |

## Deep Linking

Not applicable: the source defines no URL scheme, route, or deep-link
handling of any kind. Which pane is active is decided only by mouse events
and `NSWindow` lifecycle notifications, never by a URL.

## Localization

Not applicable: the source renders no user-facing text. It only sets a
background color and a border on a view; there is no string in this file to
localize.

## Accessibility Options

- **Reduce Motion**: Not applicable — `applyTheme(_:)` sets colors directly
  with no animation or transition of any kind; there is no motion for this
  setting to reduce.
- **Increase Contrast**: Not applicable in the sense of a distinct code path
  — the component performs no Increase-Contrast-specific branching of its
  own; all color comes from theme tokens whose values are outside this file
  (see Accessibility > Contrast for the open question on those tokens'
  actual contrast).
- **Differentiate Without Color**: NEEDS REVIEW: Not implemented in source.
  The active/inactive distinction is conveyed by outline color alone
  (`projectActivePaneOutline` vs. `projectPaneOutline`); the source defines
  no secondary, non-color cue (outline width, an icon, a pattern, a label)
  and does not read the Differentiate Without Color setting. A non-color cue,
  if one is added, is a change to `applyTheme(_:)`'s drawing, not to the
  tracking logic this recipe otherwise specifies.

## Feature Flags

Not applicable: the source contains no feature-flag check of any kind.

## Analytics

Not applicable: the source contains no analytics or telemetry call.

## Privacy

- **Data collected**: No user content. The only data held is each open
  window's currently active pane `UUID` — a value assigned by the pane's own
  view controller when it is created, not derived from anything the user
  types or enters.
- **Storage**: In-memory only, in three private collections
  (`activeByWindow`, `paneWindows`, `paneViews`) that live only as long as
  the app process; nothing in this file writes to disk, `UserDefaults`, or
  any database.
- **Transmission**: None. Nothing in this file makes a network call or
  passes its state outside the process.
- **Retention**: A window's active-id entry is removed when its active pane
  departs with no survivor (**departure-clears-active-id-when-no-pane-survives**)
  or when the window closes (**window-close-clears-active-id-silently**).
  Nothing here is persisted across an app relaunch — which pane a window was
  last active in is not restored automatically by this component.

## Logging

Not applicable: the source contains no logging call (no `os_log`, `Logger`,
or `print`) anywhere in this file.

## Platform Notes

- **SwiftUI**: There is no SwiftUI equivalent of a single, app-wide local
  `NSEvent` monitor, so the click/pointer capture still has to happen at
  whatever AppKit-hosting layer wraps the SwiftUI content. Model the tracker
  itself as a small `ObservableObject` (mirroring `ComposableTabsActivePane`,
  one instance per window/scene) exposed via `.environmentObject`, and give
  each pane a modifier that reads its own `nodeID` against the tracker's
  `activeNodeID(in:)` to pick `.overlay(RoundedRectangle(cornerRadius: 0).stroke(color, lineWidth: 2))`,
  where `color` switches between the accent and hairline tokens exactly as
  `applyTheme(_:)` does.
- **Compose (Desktop)**: Compose Desktop's `Window` maps closely to `NSWindow`,
  so hold the active-pane map as a `MutableState<UUID?>` per `Window`
  (hoisted in a `CompositionLocal`, one per window scope). Use
  `Modifier.onPointerEvent(PointerEventType.Press)` for the click path and
  `Modifier.onPointerEvent(PointerEventType.Move)` gated by the equivalent
  setting for the pointer-follows path, and `Modifier.border(2.dp, if (isActive) accent else outline)`
  for the outline, matching the always-2pt, color-only distinction this file
  draws.
- **React/Web**: The web platform has effectively one window, so the
  per-window map collapses to a single ref/state value held by an
  `ActivePaneProvider` context. Attach `mousedown`/pointer-move listeners at
  the document root in the capture phase (mirroring the one local monitor
  here, instead of one listener per pane) and toggle a `data-active`
  attribute or CSS class on the pane element to switch its outline color;
  gate pointer-move-driven switching behind a user preference the same way
  `activePaneFollowsMouse` gates it here.
- **AppKit/UIKit**: This is the source platform; see
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsActivePane.swift`.
  It is macOS-only — `NSEvent` local monitors, `NSWindow.firstResponder`/
  `makeFirstResponder`, weak `NSHashTable` collections, and
  `NSWindow.didBecomeKeyNotification`/`didResignKeyNotification` all have no
  UIKit equivalent. UIKit has no local-monitor concept and (outside iPad
  multi-window) no second window competing for keyboard focus in the same
  sense; a port to iPad multi-window would need `UIGestureRecognizer`s or a
  `UIWindow.hitTest` override plus a walk up the `UIResponder.next` chain in
  place of the `NSEvent` monitor and `makeFirstResponder` walk used here.
- **WinUI 3**: Track the active pane per `Window` (WinUI 3's per-window model
  matches `NSWindow` closely) in a `Dictionary<Window, Guid>`, mutated only
  from the UI thread — WinUI is single-threaded per dispatcher, matching this
  file's `@MainActor`. Replace the `NSEvent` local monitor with a
  `PointerPressed` handler added at the `Window.Content` root via the
  `AddHandler` overload that takes `handledEventsToo: true`, so a click is
  still seen even if an inner control already marked it handled — the WinUI
  analogue of a monitor that "sees the events before the responder chain
  does." Gate a matching root-level `PointerMoved` handler behind a setting
  equivalent to `activePaneFollowsMouse`, and behind `Window.Activated`
  state (`WindowActivationState.Deactivated` in place of "not key") and a
  check for an open modal in place of an attached sheet. For the focus walk,
  use `FocusManager.TryMoveFocusAsync`/`Control.Focus(FocusState.Programmatic)`
  starting from the hit-tested element and walking outward through its
  `VisualTreeHelper` ancestry, mirroring `takeFocus`'s innermost-first order;
  handle `Control.LosingFocus` with `args.Cancel = true` as WinUI's
  equivalent of a responder refusing to resign, and check that flag before
  calling the WinUI equivalent of `activate` — mirroring
  **focus-refusal-blocks-mouse-moved-activation**. For the chrome, wrap each
  pane's content in a `Border BorderThickness="2"` bound to a
  `SolidColorBrush` resource that switches between the app's accent brush and
  a neutral outline brush via a view-model boolean exactly like `isActive`
  here, and inset the pane's own background `Border`/`Grid` by 2px from that
  outer `Border`'s edge to reproduce `borderInset`.

## Design Decisions

- **Decision**: Pointer movement is gated behind `activePaneFollowsMouse`,
  which defaults to `false`.
  **Rationale**: Per the source's own comment, focus that moves without being
  asked to is a preference people hold strongly in both directions, and the
  surprising answer — the keys going somewhere the user did not put them —
  is judged the wrong default.
  **Approved**: pending
- **Decision**: A click activates the hit pane directly and never itself
  calls `takeFocus`; only a pointer move calls it.
  **Rationale**: A click already carries its own focus through AppKit's
  ordinary hit-test-to-first-responder path, so calling `takeFocus` for a
  click would be redundant. A move carries no such focus of its own, so
  without an explicit call the outline could move to a pane the keyboard
  never followed into.
  **Approved**: pending
- **Decision**: For a pointer move, focus is taken before the pane is
  activated, and a refusal from the outgoing responder blocks the activation
  entirely — nothing is left half-changed.
  **Rationale**: The source notes that a text field failing validation in
  `resignFirstResponder` is AppKit's ordinary way of saying "finish this
  first"; outlining the new pane anyway would point at a pane the keyboard
  is not actually in.
  **Approved**: pending
- **Decision**: A hidden pane (for example, a collapsed split) still counts
  as "live" and still holds the active id; only removal from the window ends
  its claim.
  **Rationale**: Per the source's own comment, a collapsed split is still the
  user's pane; only a pane out of the window entirely has stopped being
  somewhere the keys can go.
  **Approved**: pending
- **Decision**: `isInActivePane(_:)` is deliberately blind to whether the
  window is key.
  **Rationale**: The source states this is deliberate: which pane the user is
  working in does not change because a settings window came forward, and a
  pane that dimmed itself every time Settings opened would be reporting the
  wrong thing exactly when the user was looking at it.
  **Approved**: pending
- **Decision**: The `NSEvent` monitor is local to the app's own windows, not
  global.
  **Rationale**: This app only needs to know about the pointer inside its own
  windows, and a local monitor sees events before the responder chain does
  without requiring the accessibility permission a global monitor would need.
  **Approved**: pending
- **Decision**: `NSWindow.willCloseNotification` handling and the
  `highlightActivePane` settings-change handling are both explicitly
  dispatched onto `DispatchQueue.main`, not `RunLoop.main`.
  **Rationale**: `RunLoop.main` enqueues only in `.default` mode, so anything
  posted while AppKit tracks a mouse-down in `.eventTracking` mode (for
  example, a checkbox being clicked) would not run until the tracking loop
  ended. `DispatchQueue.main` is drained in every mode.
  **Approved**: pending
- **Decision**: Every pane's backdrop is always outlined at a constant 2pt
  width; only the border color distinguishes the active pane.
  **Rationale**: The source states that outlining only the active pane left
  every other pane reading as an unbounded field of `windowBackground`, so
  two panes side by side would look like one pane with a seam down it. A
  constant width means clicking between panes recolors a line instead of
  moving one.
  **Approved**: pending
- **Decision**: The workspace's own backdrop plane (not the pane's fill) is
  what the active-pane border is drawn against, with the pane's fill inset
  inside it.
  **Rationale**: The source states that painting the border and the pane's
  fill as one plane put a hairline of window background between a tab and
  the pane it belongs to, all the way around; the two-plane structure keeps
  the tab reading as part of the workspace instead of something stuck on top
  of it.
  **Approved**: pending
- **Decision**: `paneWindows` and `paneViews` are weak `NSHashTable`
  collections rather than strong references.
  **Rationale**: Per the source's own comments, both are convenience lists,
  never owners; a closed window or a pane that has left its window needs to
  be able to go away without this component being told twice.
  **Approved**: pending
- **Decision**: `palette.projectActivePaneOutline` is referenced by this file
  but is not defined anywhere in the `external/agenticdevelopertoolkit`
  submodule as currently vendored into this repository (that file's
  `SemanticPalette` extension defines only `projectPaneBackdrop` and
  `projectPaneOutline`); a definition for `projectActivePaneOutline` (as the
  theme's `accent` color) exists in at least one more recent revision of the
  same upstream source available on this machine, outside this repository's
  pinned submodule commit.
  **Rationale**: Recorded here as an observed fact about the state of this
  repository's vendored dependency, not a behavior of `ComposableTabsActivePane.swift`
  itself, so that whoever next bumps the `agenticdevelopertoolkit` submodule
  pointer knows this file is already written against a property that pointer
  needs to provide.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [source-fidelity](agenticdevelopercookbook://compliance/recipe-quality#source-fidelity) | passed | recipe-quality |
| [behavioral-requirements](agenticdevelopercookbook://compliance/recipe-quality#behavioral-requirements) | passed | recipe-quality |
| [completeness](agenticdevelopercookbook://compliance/recipe-quality#completeness) | passed | recipe-quality |
| [template-conformance](agenticdevelopercookbook://compliance/recipe-quality#template-conformance) | passed | recipe-quality |
| [keyboard-focus-routing](agenticdevelopercookbook://compliance/accessibility#keyboard-focus-routing) | passed | accessibility |
| [non-text-contrast](agenticdevelopercookbook://compliance/accessibility#non-text-contrast) | needs-review | accessibility |
| [theme-token-only-colors](agenticdevelopercookbook://compliance/ui#theme-token-only-colors) | passed | ui |

`keyboard-focus-routing` passes because every pointer-driven activation is
paired with a standard `NSResponder` focus change, with no private
accessibility-bypassing mechanism. `non-text-contrast` is `needs-review`
because the actual color values behind `projectPaneBackdrop`,
`projectPaneOutline`, and `projectActivePaneOutline` are chosen per theme,
outside this file, per the marker in Accessibility > Contrast.
`theme-token-only-colors` passes because every color this file reads is a
`SemanticPalette` role, never a raw literal.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial extraction from source. |
