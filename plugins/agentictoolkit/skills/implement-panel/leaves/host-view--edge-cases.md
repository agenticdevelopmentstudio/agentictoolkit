<!-- leaf: implement-panel/host-view--edge-cases · source: panel-host-view.md -->

# PanelHostView

**Rules** (cite as `implement-panel/host-view--edge-cases#<slug>`):

- `null-empty-input` MUST — setContent(nil) MUST empty the content container rather than error (clears-content-on-nil). setHelp(nil) MUST be …

## Edge Cases

- **Null/empty input**: `setContent(nil)` MUST empty the content container
  rather than error (**clears-content-on-nil**). `setHelp(nil)` MUST be
  forwarded to the presenter exactly like any other value
  (**set-help-forwards-to-presenter**); `PanelHostView.swift` performs no
  special-casing between `nil` and a populated `PanelHelp` beyond passing
  the value through.
- **Boundary values**: Not applicable in the numeric-input sense — the
  only fixed numeric value in source is the `buttonInset` constant (12pt),
  which is not client-supplied and has no minimum/maximum to test.
- **Concurrent access**: Not applicable — `PanelHostView` is a
  `@MainActor` class; the Swift compiler rejects construction or mutation
  of it from off the main actor, so there is no concurrent-access surface
  to define behavior for.
- **Error states (dependency/network failure)**: Not applicable — the
  source performs no I/O, network call, or fallible operation; every
  method is a synchronous view/property update with no failure path.
- **Offline/disconnected state**: Not applicable — `PanelHostView.swift`
  performs no networking of any kind.
- **Rapid, repeated `setContent(_:)` calls**: Each call independently
  tears down and rebuilds the content container's subviews
  (**replaces-content-on-set**); the source contains no debouncing or
  in-flight guard, so N calls in quick succession perform N full teardown
  cycles.
- **`helpPresenter` reassigned to a different, non-`nil` instance while
  the previous presenter is still retained elsewhere**: The source's
  `didSet` only ever touches `self.helpPresenter` — the *new* value — and
  never clears the previously assigned presenter's own
  `onVisibilityChange`. If a caller keeps a reference to the old presenter
  and it later fires `onVisibilityChange` on its own, this view's closure
  still runs and repaints the help button as if that stale presenter were
  still current. This is what the `didSet` implementation does, not an
  intentional safeguard.
- **`showsHelpButton` toggled while help is currently visible**: Setting
  it to `false` hides the button (**help-button-visibility**)
  but does not itself close help — `helpPresenter.isHelpVisible` and any
  window drawer/popover the presenter owns are unaffected; only this
  view's own button disappears.
- **Anchor left stale when the button hides**: Per
  **help-anchor-untouched-when-button-hidden**, `PanelHostView` does not
  clear `helpPresenter?.helpAnchorView` when `showsHelpButton` becomes
  `false` — the presenter is left pointing at a now-hidden view. What a
  presenter does with a hidden anchor (for example guarding before
  presenting) is that presenter's own contract, not `PanelHostView`'s.
