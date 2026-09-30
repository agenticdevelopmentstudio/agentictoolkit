<!-- leaf: implement-composable-tabs/active-pane--part-2 · source: composable-tabs-active-pane.md -->

# ComposableTabsActivePane — continued (part 2)

**Rules** (cite as `implement-composable-tabs/active-pane--part-2#<slug>`):

- `tracks-active-node-per-window` MUST
- `unclaimed-pane-counts-as-active` MUST
- `membership-decided-by-node-id-match` MUST
- `view-outside-any-pane-counts-as-active` MUST
- `nil-window-has-no-active-node` MUST
- `is-in-active-pane-ignores-key-window` MUST
- `arrival-claims-active-in-an-unclaimed-window` MUST
- `arrival-does-not-steal-active-from-a-live-pane` MUST
- `arrival-enables-mouse-moved-tracking-when-setting-on` MUST
- `departure-hands-off-to-a-surviving-pane` MUST
- `departure-clears-active-id-when-no-pane-survives` MUST
- `departure-of-a-non-active-pane-is-inert` MUST
- `window-close-clears-active-id-silently` MUST
- `close-and-highlight-changes-dispatch-through-the-main-queue` MUST
- `activation-is-idempotent` MUST
- `activation-posts-notification-on-change` MUST
- `setting-enabled-reaches-already-open-windows` MUST
- `accepts-mouse-moved-is-never-reset-to-false` MUST
- `event-monitor-is-local-to-the-apps-own-windows` MUST
- `clicks-are-evaluated-regardless-of-the-setting` MUST
- `mouse-moved-is-gated-by-the-setting` MUST
- `mouse-moved-is-gated-by-key-window` MUST
- `mouse-moved-is-gated-by-an-attached-sheet` MUST
- `mouse-moved-is-gated-by-arrange-mode` MUST
- `an-event-with-no-window-is-ignored` MUST
- `a-nil-content-view-means-no-pane` MUST
- `event-outside-any-pane-is-ignored` MUST
- `event-on-the-already-active-pane-is-a-no-op` MUST
- `click-activates-a-different-pane-directly` MUST
- `mouse-moved-takes-focus-before-activating` MUST
- `focus-refusal-blocks-mouse-moved-activation` MUST
- `the-event-monitor-never-consumes-an-event` MUST
- `focus-walk-proceeds-innermost-to-outermost` MUST
- `focus-walk-treats-the-current-responder-as-already-taken` MUST
- `focus-walk-stops-on-outgoing-refusal` MUST
- `focus-walk-restores-the-original-responder-on-exhaustion` MUST
- `focus-walk-reports-refused-when-restoration-fails` MUST
- `every-pane-is-always-outlined` MUST
- `the-backdrop-is-always-the-pane-backdrop-color` MUST
- `the-active-pane-uses-the-accent-outline-color` MUST
- `every-other-pane-uses-the-hairline-outline-color` MUST
- `the-accent-color-requires-a-focused-window` MUST

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
- **is-in-active-pane-ignores-key-window**: `isInActivePane(_:)` MUST return
  the same result regardless of whether its view's window is the key window;
  which pane the user is working in does not change because a different
  window came forward.
- **a-hidden-pane-remains-live**: A pane counts as "live" — eligible to hold
  the active id, or to receive it as a departure's successor — as long as its
  backdrop remains anywhere in the window, even if hidden (for example, by a
  collapsed split). Only a pane removed from the window entirely stops
  counting as live.
- **arrival-claims-active-in-an-unclaimed-window**: `paneDidAppear(_:in:)`
  MUST activate the arriving pane when no live pane (per
  **a-hidden-pane-remains-live**) already on screen in that window holds the
  active id.
- **arrival-does-not-steal-active-from-a-live-pane**: `paneDidAppear(_:in:)`
  MUST NOT change the window's active id when a live pane (per
  **a-hidden-pane-remains-live**) already on screen in that window holds it.
- **arrival-enables-mouse-moved-tracking-when-setting-on**:
  `paneDidAppear(_:in:)` MUST set the window's `acceptsMouseMovedEvents` to
  `true` whenever `activePaneFollowsMouse` is enabled, regardless of whether
  the arriving pane becomes the active one.
- **departure-hands-off-to-a-surviving-pane**: `paneDidDisappear(_:from:)`
  MUST reassign the window's active id to another live pane (per
  **a-hidden-pane-remains-live**) in the same window when the departing pane
  held the active id and at least one other live pane remains.
- **departure-clears-active-id-when-no-pane-survives**:
  `paneDidDisappear(_:from:)` MUST remove the window's active-id entry
  entirely when the departing pane held the active id and no other live pane
  (per **a-hidden-pane-remains-live**) remains in that window.
- **departure-of-a-non-active-pane-is-inert**: `paneDidDisappear(_:from:)`
  MUST NOT alter the window's active id, and MUST NOT post
  `didChangeNotification`, when the departing pane did not hold the active id.
- **window-close-clears-active-id-silently**: The component MUST remove a
  window's active-id entry when that `NSWindow` posts `willCloseNotification`,
  and MUST NOT post `didChangeNotification` when doing so.
- **close-and-highlight-changes-dispatch-through-the-main-queue**: The
  component MUST handle `NSWindow.willCloseNotification` and MUST have each
  pane backdrop handle a `highlightActivePane` change by re-dispatching onto
  `DispatchQueue.main`, not `RunLoop.main`, so the update still applies while
  AppKit is tracking a mouse event in `.eventTracking` run-loop mode.
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
- **event-monitor-is-local-to-the-apps-own-windows**: The component MUST
  install its event monitor with `NSEvent.addLocalMonitorForEvents`, not a
  global monitor, so it observes pointer events only inside this app's own
  windows and requires no accessibility permission.
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
- **an-event-with-no-window-is-ignored**: `record(_:)` MUST ignore (take no
  action for) any monitored `NSEvent` whose `window` is `nil`.
- **a-nil-content-view-means-no-pane**: `paneChain(under:in:)` MUST return
  `nil` — no pane matched — for a window whose `contentView` is `nil`, rather
  than treating any point in it as inside a pane.
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
  effective highlight setting is enabled. This check compares
  `activeNodeID(in:)` directly against the pane's own `nodeID` — it does not
  call `isInActivePane(_:)`. When the window has no recorded active id (see
  **unclaimed-pane-counts-as-active**), the comparison is against `nil`, so no
  pane draws the accent, even though `isInActivePane(_:)` would report `true`
  for a view inside any of them.
- **every-other-pane-uses-the-hairline-outline-color**: `applyTheme(_:)` MUST
  color the border with `palette.projectPaneOutline` in every case that does
  not satisfy **the-active-pane-uses-the-accent-outline-color**.
- **the-accent-color-requires-a-focused-window**: `applyTheme(_:)` MUST NOT
  use the accent border color when the pane's window is neither key nor has a
  key attached sheet, even when the pane holds that window's active id.
