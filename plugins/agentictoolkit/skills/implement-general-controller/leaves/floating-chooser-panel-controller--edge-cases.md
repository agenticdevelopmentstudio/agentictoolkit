<!-- leaf: implement-general-controller/floating-chooser-panel-controller--edge-cases · source: floating-chooser-panel-controller.md -->

# FloatingChooserPanelController

**Rules** (cite as `implement-general-controller/floating-chooser-panel-controller--edge-cases#<slug>`):

- `concurrent-access` MUST — The controller is @MainActor-isolated, so there is no defined behavior for access from another thread — none is needed …

## Edge Cases

- **Null/empty input**: `show()` guards `window` being `nil` and returns
  without effect if so (**guards-show-against-missing-window**) — in
  practice the window always exists once `init` has run, but the guard is
  present. If no screen contains the mouse location and `NSScreen.main` is
  also unavailable, `position(_:)` falls back to `window.center()` rather
  than computing an invalid origin
  (**falls-back-to-centering-without-visible-frame**).
- **Boundary values**: `topInsetFraction` is a fixed constant (0.2), not a
  configurable input, so there is no boundary range to exercise on it
  directly.
- **position-clamping**: NEEDS REVIEW: Not implemented in source. `position(_:)` computes the panel's origin from a subclass's `contentRect` and the screen's `visibleFrame` with no clamp against either edge — if `contentRect` height exceeds `visibleFrame.height * (1 - topInsetFraction)`, the computed `origin.y` goes negative and the panel renders partly below the visible frame, or off it entirely on a very short screen; resolving it requires the app team to decide whether the clamp belongs here or in each subclass's sizing.
- **Concurrent access**: The controller is `@MainActor`-isolated, so there is
  no defined behavior for access from another thread — none is needed
  because AppKit window controllers are inherently single-threaded. Within
  the main actor, the one reentrancy case the source guards against is
  `close()` being re-entered while a dismissal is already unwinding
  (`isDismissing`), covered by `guards-close-against-reentrancy` and
  `ignores-focus-loss-while-already-dismissing` above (MUST).
- **Error states**: No fallible operation exists in this file — window and
  panel construction, positioning, and dismissal have no return code or
  thrown error to handle, so there is nothing for this file to report or
  recover from.
- **Offline/disconnected state**: Not applicable — the controller performs
  no network requests and has no dependency on connectivity.
