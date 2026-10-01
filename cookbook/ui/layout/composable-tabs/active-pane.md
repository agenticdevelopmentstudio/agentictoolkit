---
id: 08bfb299-851b-4b01-a84a-6a2a13e07c12
title: Composable Tabs Active Pane
domain: agentictoolkit://cookbook/ui/layout/composable-tabs/active-pane
type: ingredient
version: 1.2.0
status: review
language: en
created: 2026-09-23
modified: '2026-09-27'
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
depends-on:
- agentictoolkit://cookbook/ui/layout/composable-tabs/leaf-pane-view
related:
- agentictoolkit://cookbook/ui/layout/composable-tabs/arrange-overlay-view
references:
- https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents(matching:handler:)
- https://developer.apple.com/documentation/appkit/nswindow/makefirstresponder(_:)
- https://developer.apple.com/documentation/foundation/runloop/mode-swift.struct/eventtracking
- https://www.w3.org/WAI/WCAG21/Understanding/non-text-contrast.html
approved-by: ''
approved-date: ''
---

# Composable Tabs Active Pane

## Overview

The active pane tracker is a single, app-wide tracker that tracks,
independently for each open window, which composable-tabs pane the user is
currently working in — the one they last clicked in, or, with the
pointer-follows setting on, the one under the pointer. The platform provides
no "the input focus changed" notification of its own, and a pane's own
content intercepts pointer events before a pane could see them itself, so
the tracker installs one pointer-event monitor for the whole app (primary
click, secondary click, pointer move) instead of every pane installing a
monitor of its own, and answers "which pane is this point in" with one hit
test rather than a second implementation of it living in a tracking area.

This ingredient also covers the pane backdrop view — a pane's backdrop that
draws the "this is the pane you are working in" border. It is one view — not
an overlay — so the border can never end up under the pane's own content,
and it registers its arrival and departure with the tracker as it moves in
and out of a window, and repaints whenever the tracker, the window's focus
state, or the highlight setting changes.

Neither part renders or exposes anything else: no title, no icon, no
interactive control of its own. The chrome a pane wears beyond this backdrop
(title bar, gear menu, content identifier) belongs to the pane's own view
controller, not to this component, and is out of scope for this ingredient.

## Behavioral Requirements

- **tracks-active-node-per-window**: The component MUST maintain,
  independently for each window, at most one active pane node id at a time.
- **unclaimed-pane-counts-as-active**: Checking whether a view is in the
  active pane MUST return `true` for a view inside a pane backdrop whose
  window has no active node id recorded yet.
- **membership-decided-by-node-id-match**: Checking whether a view is in the
  active pane MUST return `true` for a view inside a pane backdrop only when
  that backdrop's node id equals the window's recorded active node id (or the
  window has none recorded, per **unclaimed-pane-counts-as-active**), and
  MUST return `false` otherwise.
- **view-outside-any-pane-counts-as-active**: Checking whether a view is in
  the active pane MUST return `true` for a view that has no pane backdrop
  anywhere among its ancestor views.
- **nil-window-has-no-active-node**: Looking up the active node id for a
  window MUST return none when passed no window.
- **is-in-active-pane-ignores-key-window**: Checking whether a view is in the
  active pane MUST return the same result regardless of whether its view's
  window is the focused window; which pane the user is working in does not
  change because a different window came forward.
- **a-hidden-pane-remains-live**: A pane counts as "live" — eligible to hold
  the active id, or to receive it as a departure's successor — as long as its
  backdrop remains anywhere in the window, even if hidden (for example, by a
  collapsed split). Only a pane removed from the window entirely stops
  counting as live.
- **arrival-claims-active-in-an-unclaimed-window**: A pane's arrival MUST
  activate the arriving pane when no live pane (per
  **a-hidden-pane-remains-live**) already on screen in that window holds the
  active id.
- **arrival-does-not-steal-active-from-a-live-pane**: A pane's arrival MUST
  NOT change the window's active id when a live pane (per
  **a-hidden-pane-remains-live**) already on screen in that window holds it.
- **arrival-enables-mouse-moved-tracking-when-setting-on**: A pane's arrival
  MUST enable pointer-move tracking on the window whenever the
  pointer-follows setting is enabled, regardless of whether the arriving pane
  becomes the active one.
- **departure-hands-off-to-a-surviving-pane**: A pane's departure MUST
  reassign the window's active id to another live pane (per
  **a-hidden-pane-remains-live**) in the same window when the departing pane
  held the active id and at least one other live pane remains.
- **departure-clears-active-id-when-no-pane-survives**: A pane's departure
  MUST remove the window's active-id entry entirely when the departing pane
  held the active id and no other live pane (per
  **a-hidden-pane-remains-live**) remains in that window.
- **departure-of-a-non-active-pane-is-inert**: A pane's departure MUST NOT
  alter the window's active id, and MUST NOT post a change notification, when
  the departing pane did not hold the active id.
- **window-close-clears-active-id-silently**: The component MUST remove a
  window's active-id entry when that window closes, and MUST NOT post a
  change notification when doing so.
- **close-and-highlight-changes-dispatch-through-the-main-queue**: The
  component MUST handle a window's close, and MUST have each pane backdrop
  handle a highlight-setting change, by dispatching onto the main work queue
  rather than a mechanism that pauses while an interaction is in progress, so
  the update still applies while the platform is in the middle of tracking a
  pointer gesture.
- **activation-is-idempotent**: Activating a node id MUST have no effect, and
  MUST NOT post a change notification, when the given node id already equals
  the window's current active id.
- **activation-posts-notification-on-change**: Activating a node id MUST post
  a change notification, with the window as its subject, whenever it changes
  the window's active id.
- **setting-enabled-reaches-already-open-windows**: Turning the
  pointer-follows setting on MUST enable pointer-move tracking on every
  window the component is already tracking, not only on windows opened after
  the change.
- **accepts-mouse-moved-is-never-reset-to-false**: The component MUST NOT
  disable pointer-move tracking on a window once enabled, even when the
  pointer-follows setting is or becomes disabled; disabling the setting only
  stops pointer-move events from being acted on, not received.
- **event-monitor-is-local-to-the-apps-own-windows**: The component MUST
  install its event monitor as a local monitor, not a global one, so it
  observes pointer events only inside this app's own windows and requires no
  special system permission.
- **clicks-are-evaluated-regardless-of-the-setting**: The event monitor MUST
  evaluate every primary-click and secondary-click event regardless of the
  pointer-follows setting.
- **mouse-moved-is-gated-by-the-setting**: A pointer-move event MUST be
  ignored unless the pointer-follows setting is enabled.
- **mouse-moved-is-gated-by-key-window**: A pointer-move event MUST be
  ignored when its window is not the focused window.
- **mouse-moved-is-gated-by-an-attached-sheet**: A pointer-move event MUST be
  ignored when its window has an attached sheet.
- **mouse-moved-is-gated-by-arrange-mode**: A pointer-move event MUST be
  ignored when arrange mode is enabled for that window.
- **an-event-with-no-window-is-ignored**: Recording an event MUST ignore
  (take no action for) any monitored event whose window is unset.
- **a-nil-content-view-means-no-pane**: Resolving a pane chain under a point
  MUST return none — no pane matched — for a window whose content view is
  unset, rather than treating any point in it as inside a pane.
- **event-outside-any-pane-is-ignored**: An event whose hit-tested point does
  not land inside any pane backdrop MUST be ignored.
- **event-on-the-already-active-pane-is-a-no-op**: An event, click or move,
  that hit-tests to the pane already holding the window's active id MUST
  cause no state change.
- **click-activates-a-different-pane-directly**: A primary or secondary click
  that hit-tests to a pane other than the currently active one MUST activate
  that pane.
- **mouse-moved-takes-focus-before-activating**: A pointer-move event that
  hit-tests to a pane other than the currently active one MUST attempt to
  move input focus into that pane before the pane is activated.
- **focus-refusal-blocks-mouse-moved-activation**: When the outgoing
  input-focus holder refuses to give up focus during the focus attempt a
  pointer-move event triggers, the hit-tested pane MUST NOT be activated.
- **the-event-monitor-never-consumes-an-event**: The local event monitor MUST
  return every event it observes unmodified.
- **focus-walk-proceeds-innermost-to-outermost**: Taking input focus within a
  hit-tested chain MUST offer input-focus status to the chain of views in
  innermost-to-outermost order, stopping at the first view that accepts it.
- **focus-walk-treats-the-current-responder-as-already-taken**: Taking input
  focus MUST treat a candidate view that already holds input focus as taken,
  without attempting to reassign focus to it again.
- **focus-walk-stops-on-outgoing-refusal**: Taking input focus MUST stop the
  walk and report a refusal the moment a focus-assignment attempt leaves the
  outgoing focus holder still in place.
- **focus-walk-restores-the-original-responder-on-exhaustion**: When no
  candidate in the chain accepts input-focus status, taking input focus MUST
  attempt to restore the original focus holder and, if that succeeds, MUST
  report that there was nowhere to put the keys.
- **focus-walk-reports-refused-when-restoration-fails**: When no candidate
  accepts input-focus status and the attempt to restore the original focus
  holder fails, taking input focus MUST report a refusal.
- **every-pane-is-always-outlined**: Applying the theme MUST draw a 2-point
  border on every pane backdrop, whether or not it is the active pane.
- **the-backdrop-is-always-the-pane-backdrop-color**: Applying the theme MUST
  set the view's background to the theme's pane-backdrop color regardless of
  active state.
- **the-active-pane-uses-the-accent-outline-color**: Applying the theme MUST
  color the border with the theme's active-pane-outline color when, and only
  when, the pane holds its window's active id, the window is focused, and the
  effective highlight setting is enabled. This check compares the active
  node id directly against the pane's own node id — it does not go through
  the "is in active pane" check. When the window has no recorded active id
  (see **unclaimed-pane-counts-as-active**), the comparison is against none,
  so no pane draws the accent, even though checking whether a view is in the
  active pane would report `true` for a view inside any of them.
- **every-other-pane-uses-the-hairline-outline-color**: Applying the theme
  MUST color the border with the theme's pane-outline color in every case
  that does not satisfy **the-active-pane-uses-the-accent-outline-color**.
- **the-accent-color-requires-a-focused-window**: Applying the theme MUST NOT
  use the accent border color when the pane's window is neither focused nor
  has a focused attached sheet, even when the pane holds that window's
  active id.
- **an-attached-sheet-counts-the-window-as-focused**: Applying the theme MUST
  treat the pane's window as focused when that window's attached sheet is the
  focused window, even when the window itself is not focused.
- **a-theme-override-takes-precedence-over-the-user-setting**: Applying the
  theme MUST use the current theme's project-level highlight override when
  the theme sets one, and MUST fall back to the user's highlight setting only
  when the theme does not.
- **the-fill-is-inset-from-the-backdrop-edges**: The pane's fill subview MUST
  be constrained on all four edges to the backdrop's own border inset (2
  points) inside the backdrop's own bounds.
- **the-fill-is-the-first-subview**: The fill subview MUST be added to the
  backdrop before any other subview, so chrome added later renders above it.
- **a-window-change-reports-departure-before-arrival**: Handling a change of
  window MUST report the backdrop's departure from its previous window, when
  it had one and it differs from the new one, before reporting its arrival in
  the new window.
- **the-backdrop-repaints-on-its-own-windows-activation-change**: The
  backdrop MUST reapply its theme when a tracker change notification is
  posted with its own window as the subject, and MUST ignore that
  notification for any other window.
- **the-backdrop-repaints-on-any-key-window-change**: The backdrop MUST
  reapply its theme whenever any window becomes or loses focus, not only its
  own.
- **the-backdrop-repaints-on-a-highlight-setting-change**: The backdrop MUST
  reapply its theme when the highlight setting changes.

## Appearance

- **Corner radius**: None. The backdrop is a plain rectangular view layer
  with no corner radius set.
- **Padding**: Not applicable in the padding sense; the backdrop's fill
  subview is inset from the backdrop's own edges by the border inset (2pt) on
  all four sides, leaving that band for the border to draw in.
- **Font**: Not applicable. The component draws no text.
- **Background**: The theme's pane-backdrop color (a theme-overridable role,
  falling back to the elevated-surface role when the theme sets no override
  for it) fills the backdrop's layer; the fill subview inside it is painted
  with the window-background role.
- **Foreground/Text**: Not applicable. The component draws no text or icon.
- **Border**: 2 points wide on every pane, always. Color is the theme's
  active-pane-outline color for the active pane in a focused window with
  highlighting enabled, and the theme's pane-outline color otherwise.
- **Shadow**: None. The source sets no shadow on the backdrop.
- **Min/Max size**: None imposed by this file. The backdrop is sized by its
  pane's own layout (constraints applied by the surrounding pane view
  controller, not by this file).

## States

| State | Appearance change |
|-------|--------------------|
| No pane has claimed the window yet | No pane's backdrop draws the accent color; every pane reads as "inactive" (hairline outline) until the first arrival claims the spot. |
| Active pane, window focused, highlighting enabled | 2pt border in the active-pane-outline color; backdrop in the pane-backdrop color. |
| Active pane, window not focused (not focused and no focused attached sheet) | 2pt border in the pane-outline color, same as an inactive pane. |
| Active pane, highlighting disabled (by user setting or theme override) | 2pt border in the pane-outline color, same as an inactive pane. |
| Inactive pane | 2pt border in the pane-outline color; backdrop in the pane-backdrop color. |
| Arrange mode enabled in the window | Pointer movement no longer changes the active pane; clicks still do. |
| Window has an attached sheet | Pointer movement no longer changes the active pane in that window; the sheet itself has the keys. |

## Accessibility

- **Role/traits**: Not applicable. The pane backdrop sets no accessibility
  role, label, or element flag of its own anywhere in the source — it is a
  backdrop, not a control. Any role or label a pane's actual content needs
  belongs to that content's own view controller, which is out of scope for
  this file (see Overview).
- **Keyboard/assistive-technology navigation**: This is the file's central
  accessibility-relevant behavior. Every pointer-driven pane switch (gated by
  the pointer-follows setting) is paired with an ordinary input-focus change,
  using the same focus-assignment mechanism a click already uses (see
  **mouse-moved-takes-focus-before-activating**,
  **focus-walk-proceeds-innermost-to-outermost**, and
  **focus-refusal-blocks-mouse-moved-activation**). Because focus moves
  through the standard focus-chain mechanism rather than a private one, the
  platform's own focus-follows-input-focus behavior for assistive technology
  applies without anything further from this file; the component defines no
  separate accessibility-notification call of its own, and none is required,
  because the underlying focus change is already the standard, observable
  one.
- **Minimum tap target**: Not applicable. The pane backdrop is a full-bleed
  backdrop sized by its enclosing pane's own layout; it is not a discrete
  tappable control with an independently sized hit target, and the source
  treats it as neither a button nor a control.
- **contrast**: NEEDS REVIEW: Not implemented in source. The pane-backdrop,
  pane-outline, and active-pane-outline colors are theme-overridable roles
  whose actual values are chosen per theme (see the Theme Editor's Project
  topic), not fixed in this component, so the contrast between the active
  border and its adjacent backdrop cannot be computed from this component
  alone; resolvable only by whoever audits each shipped theme's actual token
  values against a numeric contrast threshold (e.g. WCAG 1.4.11 non-text
  contrast, 3:1) for this border-against-backdrop pairing.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| CTA-01 | tracks-active-node-per-window | Two windows, each with panes activated independently | Each window's active id is independent of the other's |
| CTA-02 | unclaimed-pane-counts-as-active | A pane's backdrop in a window with no recorded active id | Checking whether a view is in the active pane returns `true` for a view inside that backdrop |
| CTA-03 | membership-decided-by-node-id-match | Two panes in one window, one active | Checking membership returns `true` for a view inside the active pane's backdrop and `false` for a view inside the other |
| CTA-04 | view-outside-any-pane-counts-as-active | A view with no pane backdrop ancestor (e.g. a standalone panel) | Checking whether it is in the active pane returns `true` |
| CTA-05 | nil-window-has-no-active-node | Look up the active node id for no window | Returns none |
| CTA-06 | arrival-claims-active-in-an-unclaimed-window | The first pane arrives in a fresh window | That pane becomes the active one |
| CTA-07 | arrival-does-not-steal-active-from-a-live-pane | A window already has an active pane; a second pane arrives | The active id is unchanged |
| CTA-08 | arrival-enables-mouse-moved-tracking-when-setting-on | Pointer-follows setting enabled; a second (non-claiming) pane appears | Pointer-move tracking is enabled on the window |
| CTA-09 | departure-hands-off-to-a-surviving-pane | The active pane departs while a sibling pane remains in the window | The sibling becomes the new active pane |
| CTA-10 | departure-clears-active-id-when-no-pane-survives | The active pane departs and it was the window's only pane | The active node id lookup returns none afterward |
| CTA-11 | departure-of-a-non-active-pane-is-inert | A non-active pane departs | Active id is unchanged; no change notification is posted |
| CTA-12 | window-close-clears-active-id-silently | The window closes | The active node id lookup returns none for that window afterward; no change notification is observed |
| CTA-13 | activation-is-idempotent | Activate a node id already active | No state change; no notification posted |
| CTA-14 | activation-posts-notification-on-change | Activate a different node id | A change notification is posted with that window as its subject |
| CTA-15 | setting-enabled-reaches-already-open-windows | Two windows already tracked, then the pointer-follows setting is turned on | Both windows have pointer-move tracking enabled |
| CTA-16 | accepts-mouse-moved-is-never-reset-to-false | Pointer-follows setting turned on then off again | Pointer-move tracking remains enabled on the window |
| CTA-17 | clicks-are-evaluated-regardless-of-the-setting | Pointer-follows setting disabled; a primary click lands on a different pane | That pane is activated |
| CTA-18 | mouse-moved-is-gated-by-the-setting | Pointer-follows setting disabled; pointer moves to a different pane | Active pane is unchanged |
| CTA-19 | mouse-moved-is-gated-by-key-window | Pointer-follows setting enabled; pointer moves over a non-focused window's pane | Active pane is unchanged |
| CTA-20 | mouse-moved-is-gated-by-an-attached-sheet | Window has an attached sheet; pointer moves over one of its panes | Active pane is unchanged |
| CTA-21 | mouse-moved-is-gated-by-arrange-mode | Arrange mode enabled in the window; pointer moves over a different pane | Active pane is unchanged |
| CTA-22 | event-outside-any-pane-is-ignored | A click lands outside every pane's backdrop | No state change |
| CTA-23 | event-on-the-already-active-pane-is-a-no-op | A click or pointer move lands on the already-active pane | No state change; no notification posted |
| CTA-24 | click-activates-a-different-pane-directly | A primary click lands on a non-active pane | That pane becomes active |
| CTA-25 | mouse-moved-takes-focus-before-activating | Pointer-follows setting enabled; pointer moves onto a non-active pane containing a focusable view | Focus moves to the innermost focusable view before the pane is activated |
| CTA-26 | focus-refusal-blocks-mouse-moved-activation | Outgoing focus holder refuses to give up focus; pointer moves onto a non-active pane | Active pane is unchanged; input focus is unchanged |
| CTA-27 | the-event-monitor-never-consumes-an-event | A primary click lands on a view with its own pointer-down handling, while the local monitor's handler runs first | The hit-tested view's own pointer-down handling is still invoked after the monitor's handler returns the event unmodified |
| CTA-28 | focus-walk-proceeds-innermost-to-outermost | A pane whose innermost hit-tested view refuses focus but an outer one accepts | The outer, focus-accepting view takes input focus |
| CTA-29 | focus-walk-treats-the-current-responder-as-already-taken | The innermost hit-tested view already holds input focus | Taking focus reports success without reassigning focus again |
| CTA-30 | focus-walk-stops-on-outgoing-refusal | The current focus holder refuses to give up focus | Taking focus reports refusal; the walk does not continue to further candidates |
| CTA-31 | focus-walk-restores-the-original-responder-on-exhaustion | Every view in the hit-tested chain reports that it can accept focus but declines to actually take it, so each focus-assignment attempt gives up the outgoing holder yet leaves the window itself holding focus before the walk tries the next candidate | After the walk exhausts every candidate, taking focus reassigns the original focus holder and it succeeds, restoring it; taking focus reports that there was nowhere to put the keys |
| CTA-32 | focus-walk-reports-refused-when-restoration-fails | No candidate accepts focus and restoring the original focus holder fails | Taking focus reports refusal |
| CTA-33 | every-pane-is-always-outlined | Any pane, active or not | The border width is `2` |
| CTA-34 | the-backdrop-is-always-the-pane-backdrop-color | Any pane, active or not | The background equals the theme's pane-backdrop color |
| CTA-35 | the-active-pane-uses-the-accent-outline-color | Pane is active, its window is focused, highlighting enabled | The border color equals the theme's active-pane-outline color |
| CTA-36 | every-other-pane-uses-the-hairline-outline-color | Pane is inactive (or active but window unfocused, or highlighting disabled) | The border color equals the theme's pane-outline color |
| CTA-37 | the-accent-color-requires-a-focused-window | Pane is active but its window is not focused and has no focused attached sheet | The border color equals the theme's pane-outline color, not the accent |
| CTA-38 | an-attached-sheet-counts-the-window-as-focused | Window is not focused but its attached sheet is focused; pane is active | The border color equals the theme's active-pane-outline color |
| CTA-39 | a-theme-override-takes-precedence-over-the-user-setting | Theme's highlight override set to `false`, the user's highlight setting set to `true` | The pane is drawn as not highlighted |
| CTA-40 | the-fill-is-inset-from-the-backdrop-edges | Backdrop laid out at a known frame | The fill subview's frame equals the backdrop's bounds inset by 2pt on every edge |
| CTA-41 | the-fill-is-the-first-subview | Backdrop after construction | The fill is the first subview |
| CTA-42 | a-window-change-reports-departure-before-arrival | A backdrop is moved from window A to window B | Window A's departure handling completes before window B's arrival handling begins |
| CTA-43 | the-backdrop-repaints-on-its-own-windows-activation-change | A tracker change notification posted for the backdrop's own window | Applying the theme is invoked; posting it for a different window does not invoke it |
| CTA-44 | the-backdrop-repaints-on-any-key-window-change | Any window becomes or loses focus | Applying the theme is invoked on every tracked backdrop, including ones in other windows |
| CTA-45 | the-backdrop-repaints-on-a-highlight-setting-change | The highlight setting changes | Applying the theme is invoked |
| CTA-46 | a-hidden-pane-remains-live | A pane's backdrop is hidden by a collapsed split but stays in the window; its window's active pane then departs | The hidden pane is offered as the successor in **departure-hands-off-to-a-surviving-pane** |
| CTA-47 | is-in-active-pane-ignores-key-window | A view inside the active pane's backdrop, queried while its window is not the focused window | Checking membership still returns `true`, the same as when the window is focused |
| CTA-48 | an-event-with-no-window-is-ignored | A monitored event whose window is unset | No state change; recording the event takes no action |
| CTA-49 | a-nil-content-view-means-no-pane | A window whose content view is unset receives a monitored event | Resolving the pane chain returns none; the event is ignored |
| CTA-50 | event-monitor-is-local-to-the-apps-own-windows | A pointer event delivered to a window belonging to a different application | The monitor never observes it; no pane in this app is affected |
| CTA-51 | close-and-highlight-changes-dispatch-through-the-main-queue | The window closes, or the highlight setting changes, while the platform is tracking a pointer-down gesture | The active-id removal or backdrop repaint still applies before the tracking gesture ends, because the handler is queued on the main work queue rather than a mechanism that pauses during the gesture |
| CTA-52 | the-active-pane-uses-the-accent-outline-color | No pane in a window has claimed the active id; applying the theme runs for any pane in it | The border color equals the theme's pane-outline color for every pane in the window, not the accent, even though checking membership reports `true` for a view in any of them |

## Edge Cases

- Null/empty input: Looking up the active node id for a window MUST return
  none rather than trapping or treating a missing window as any particular
  window's state.
- Null/empty input: An event with no associated window MUST be ignored when
  recording events (see **an-event-with-no-window-is-ignored**).
- Null/empty input: A window whose content view is unset MUST be treated as
  having no pane under any point (see **a-nil-content-view-means-no-pane**).
- Boundary values: A window with zero panes MUST have no entry in the active
  id map, and any view queried against that window (there being no pane to
  contain it) counts as active per **view-outside-any-pane-counts-as-active**.
- Boundary values: A window with exactly one pane MUST have that pane hold
  the active id once it appears, per **arrival-claims-active-in-an-unclaimed-window**,
  and MUST have no active pane left once it departs, per
  **departure-clears-active-id-when-no-pane-survives**.
- Concurrent access: The whole component is confined to a single thread;
  every mutation of its window/pane bookkeeping happens there, so concurrent
  access from multiple threads is not a case this file has to handle. Two
  sources that could otherwise race with an in-progress pointer-tracking
  gesture — a window closing, and a highlight-setting change — are explicitly
  re-dispatched onto the main work queue (not a mechanism that pauses during
  the gesture) so a change made while the platform tracks a pointer-down
  gesture is still applied, rather than being deferred until the gesture
  ends.
- Error states: The only "failure" outcome in this file is a view refusing
  input-focus status. This MUST be handled internally by taking focus's
  three-way outcome (taken / nowhere-to-put / refused) as described above; it
  is never surfaced to a caller, logged, or shown to the user — there is no
  user-visible error state for a focus refusal beyond the outline and
  keyboard simply not moving.
- Offline/disconnected: Not applicable. The component makes no network call
  and has no server-backed state; it is a pure in-memory, single-process
  tracker of per-window UI state.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|--------------|
| `activePaneFollowsMouse` | boolean setting | `false` | Whether pointer movement, not just clicks, can change the active pane and hand it the keyboard. |
| `highlightActivePane` | boolean setting | `true` | Whether the active pane's border is drawn in the accent color at all, unless overridden per theme. |
| `project.highlightActivePane` | boolean or unset (per-theme override) | unset (falls through to `highlightActivePane`) | A theme's own override of the same highlight toggle, edited in the Theme Editor's Project topic. |
| `borderInset` | number (points) | `2` | How far the pane's own fill is held off the backdrop's edge, in points, leaving room for the border. |

## Deep Linking

Not applicable: the source defines no URL scheme, route, or deep-link
handling of any kind. Which pane is active is decided only by pointer events
and window lifecycle notifications, never by a URL.

## Localization

Not applicable: the source renders no user-facing text. It only sets a
background color and a border on a view; there is no string in this file to
localize.

## Accessibility Options

- **Reduce Motion**: Not applicable — applying the theme sets colors
  directly with no animation or transition of any kind; there is no motion
  for this setting to reduce.
- **Increase Contrast**: Not applicable in the sense of a distinct code path
  — the component performs no Increase-Contrast-specific branching of its
  own; all color comes from theme tokens whose values are outside this file
  (see Accessibility > the open question on contrast).
- **Differentiate Without Color**: The active/inactive distinction is
  conveyed by outline color alone (the active-pane-outline color vs. the
  pane-outline color); the source defines no secondary, non-color cue
  (outline width, an icon, a pattern, a label) and does not read the
  Differentiate Without Color setting. A non-color cue, if one is added, is a
  change to the theme-application drawing, not to the tracking logic this
  ingredient otherwise specifies.

## Feature Flags

Not applicable: the source contains no feature-flag check of any kind.

## Analytics

Not applicable: the source contains no analytics or telemetry call.

## Privacy

- **Data collected**: No user content. The only data held is each open
  window's currently active pane identifier — a value assigned by the pane's
  own view controller when it is created, not derived from anything the user
  types or enters.
- **Storage**: In-memory only, in a small number of private collections that
  live only as long as the app process; nothing in this file writes to disk,
  persistent settings storage, or any database.
- **Transmission**: None. Nothing in this file makes a network call or
  passes its state outside the process.
- **Retention**: A window's active-id entry is removed when its active pane
  departs with no survivor (**departure-clears-active-id-when-no-pane-survives**)
  or when the window closes (**window-close-clears-active-id-silently**).
  Nothing here is persisted across an app relaunch — which pane a window was
  last active in is not restored automatically by this component.

## Logging

Not applicable: the source contains no logging call of any kind anywhere in
this file.

## Platform Notes

- **SwiftUI**: There is no SwiftUI equivalent of a single, app-wide local
  `NSEvent` monitor, so the click/pointer capture still has to happen at
  whatever AppKit-hosting layer wraps the SwiftUI content. Model the tracker
  itself as a single, app-wide `ObservableObject` — mirroring
  `ComposableTabsActivePane.shared`, one instance keyed internally by window,
  not one instance per window/scene — exposed via `.environmentObject`, and
  give each pane a modifier that reads its own `nodeID` against the tracker's
  `activeNodeID(in:)` to pick `.overlay(Rectangle().strokeBorder(color, lineWidth: 2))`,
  so the stroke stays inside the edge the way the inset border does here,
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
  place of the `NSEvent` monitor and `makeFirstResponder` walk used here. The
  main-queue-versus-run-loop-mode distinction behind
  **close-and-highlight-changes-dispatch-through-the-main-queue** is
  `DispatchQueue.main` (drained in every run-loop mode) versus `RunLoop.main`
  (enqueued only in `.default` mode, so it would stall while the platform
  tracks a mouse-down in `.eventTracking` mode).
- **WinUI 3**: Track the active pane per `Window` (WinUI 3's per-window model
  matches `NSWindow` closely) in a `Dictionary<Window, Guid>`, mutated only
  from the UI thread — WinUI is single-threaded per dispatcher, matching this
  file's confinement to one thread — and remove a window's entry when its
  `Window.Closed` event fires, mirroring how the source clears
  `activeByWindow` on `NSWindow.willCloseNotification` (see
  **close-and-highlight-changes-dispatch-through-the-main-queue** and
  **window-close-clears-active-id-silently**) rather than relying on garbage
  collection to age the entry out — `Guid` is a value type, so a
  `ConditionalWeakTable` cannot hold it directly the way the source's weak
  `NSHashTable`s hold reference types. Replace the `NSEvent` local monitor with a
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
  `VisualTreeHelper` ancestry, mirroring the innermost-first order taking
  focus uses; handle `Control.LosingFocus` with `args.Cancel = true` as
  WinUI's equivalent of a responder refusing to resign, and check that flag
  before calling the WinUI equivalent of `activate` — mirroring
  **focus-refusal-blocks-mouse-moved-activation**. For the chrome, wrap each
  pane's content in a `Border BorderThickness="2"` bound to a
  `SolidColorBrush` resource that switches between the app's accent brush and
  a neutral outline brush via a view-model boolean exactly like `isActive`
  here, and inset the pane's own background `Border`/`Grid` by 2px from that
  outer `Border`'s edge to reproduce `borderInset`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsActivePane.swift` |

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
  **Rationale (AppKit)**: A click already carries its own focus through
  AppKit's ordinary hit-test-to-first-responder path, so calling `takeFocus`
  for a click would be redundant. A move carries no such focus of its own, so
  without an explicit call the outline could move to a pane the keyboard
  never followed into.
  **Approved**: pending
- **Decision**: For a pointer move, focus is taken before the pane is
  activated, and a refusal from the outgoing responder blocks the activation
  entirely — nothing is left half-changed.
  **Rationale (AppKit)**: The source notes that a text field failing
  validation in `resignFirstResponder` is AppKit's ordinary way of saying
  "finish this first"; outlining the new pane anyway would point at a pane
  the keyboard is not actually in.
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
  **Rationale (AppKit)**: The source states this is deliberate: which pane
  the user is working in does not change because a settings window came
  forward, and a pane that dimmed itself every time Settings opened would be
  reporting the wrong thing exactly when the user was looking at it.
  **Approved**: pending
- **Decision**: The `NSEvent` monitor is local to the app's own windows, not
  global.
  **Rationale (AppKit)**: This app only needs to know about the pointer
  inside its own windows, and a local monitor sees events before the
  responder chain does without requiring the accessibility permission a
  global monitor would need.
  **Approved**: pending
- **Decision**: `NSWindow.willCloseNotification` handling and the
  `highlightActivePane` settings-change handling are both explicitly
  dispatched onto `DispatchQueue.main`, not `RunLoop.main`.
  **Rationale (AppKit)**: `RunLoop.main` enqueues only in `.default` mode, so
  anything posted while AppKit tracks a mouse-down in `.eventTracking` mode
  (for example, a checkbox being clicked) would not run until the tracking
  loop ended. `DispatchQueue.main` is drained in every mode.
  **Approved**: pending
- **Decision**: Every pane's backdrop is always outlined at a constant 2pt
  width; only the border color distinguishes the active pane.
  **Rationale**: The source states that outlining only the active pane left
  every other pane reading as an unbounded field of the window-background
  role, so two panes side by side would look like one pane with a seam down
  it. A constant width means clicking between panes recolors a line instead
  of moving one.
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
  **Rationale (AppKit)**: Per the source's own comments, both are
  convenience lists, never owners; a closed window or a pane that has left
  its window needs to be able to go away without this component being told
  twice.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [focus-management](agenticdevelopercookbook://compliance/accessibility#focus-management) | passed | accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | accessibility |

`focus-management` passes because every pointer-driven activation is
paired with a standard `NSResponder` focus change, with no private
accessibility-bypassing mechanism. `contrast-ratio` is `partial` because
the actual color values behind `projectPaneBackdrop`, `projectPaneOutline`,
and `projectActivePaneOutline` are chosen per theme, outside this file, per
the open question on contrast.

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial extraction from source. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: cited specific APIs and WCAG 1.4.11 instead of the HIG landing page; defined "live" pane and cross-referenced it from the arrival/departure requirements; added five untested behaviors (key-window blindness, nil-window and nil-content-view guards, the local-not-global monitor, and the main-queue dispatch for close/highlight changes) as MUST requirements with conformance vectors; clarified that `applyTheme` compares `activeNodeID(in:)` directly rather than calling `isInActivePane` and added a vector for an unclaimed window; corrected the SwiftUI platform note's per-scene/app-wide contradiction and its `RoundedRectangle(cornerRadius: 0)` stroke; corrected the WinUI 3 note's strong-dictionary lifecycle; tightened CTA-27 and CTA-31 to concrete, reproducible setups; named the `elevatedSurface` fallback for the pane backdrop color; moved the vendored-submodule gap out of Design Decisions, named the upstream commit that supplies it, and marked `source-fidelity`/`completeness`/`non-text-contrast` `partial` accordingly; populated `depends-on`/`related` with the sibling ingredients this file actually composes and observes; and fixed the frontmatter date quoting. |
| 1.1.1 | 2026-09-23 | Mike Fullerton | Compliance: removed rows for checks absent from the cookbook catalog, remapped keyboard-focus-routing to focus-management, remapped non-text-contrast to contrast-ratio |
| 1.1.2 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.3 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/layout/composable-tabs/. |
