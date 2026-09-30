<!-- leaf: implement-composable-tabs/active-pane--test-vectors · source: composable-tabs-active-pane.md -->

# ComposableTabsActivePane

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
| CTA-27 | the-event-monitor-never-consumes-an-event | A `leftMouseDown` lands on a view that overrides `mouseDown(with:)`, while the local monitor's handler runs first | The hit-tested view's `mouseDown(with:)` is still invoked after the monitor's handler returns the event unmodified |
| CTA-28 | focus-walk-proceeds-innermost-to-outermost | A pane whose innermost hit-tested view refuses focus but an outer one accepts | The outer, focus-accepting view becomes first responder |
| CTA-29 | focus-walk-treats-the-current-responder-as-already-taken | The innermost hit-tested view is already first responder | `takeFocus` reports success without calling `makeFirstResponder` again |
| CTA-30 | focus-walk-stops-on-outgoing-refusal | The current first responder refuses to resign | `takeFocus` reports refusal; the walk does not continue to further candidates |
| CTA-31 | focus-walk-restores-the-original-responder-on-exhaustion | Every view in the hit-tested chain reports `acceptsFirstResponder == true` but declines `becomeFirstResponder()`, so each `makeFirstResponder` call resigns the outgoing responder yet leaves `window.firstResponder` as the window itself before the walk tries the next candidate | After the walk exhausts every candidate, `takeFocus` calls `makeFirstResponder` with the original first responder and it succeeds, restoring it; `takeFocus` returns `.nowhereToPut` |
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
| CTA-46 | a-hidden-pane-remains-live | A pane's backdrop is hidden by a collapsed split but stays in the window; its window's active pane then departs | The hidden pane is offered as the successor in **departure-hands-off-to-a-surviving-pane** |
| CTA-47 | is-in-active-pane-ignores-key-window | A view inside the active pane's backdrop, queried while its window is not the key window | `isInActivePane` still returns `true`, the same as when the window is key |
| CTA-48 | an-event-with-no-window-is-ignored | A monitored `NSEvent` whose `window` is `nil` | No state change; `record(_:)` takes no action |
| CTA-49 | a-nil-content-view-means-no-pane | A window whose `contentView` is `nil` receives a monitored event | `paneChain(under:in:)` returns `nil`; the event is ignored |
| CTA-50 | event-monitor-is-local-to-the-apps-own-windows | A pointer event delivered to a window belonging to a different application | The monitor never observes it; no pane in this app is affected |
