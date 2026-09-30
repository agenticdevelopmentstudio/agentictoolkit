<!-- leaf: implement-general-controller/single-window-controller--edge-cases · source: single-window-controller.md -->

# SingleWindowController

## Edge Cases

- **Empty `windowID`**: `WindowRegistry.register(_:)` silently skips
  registration when `windowID` is empty; the controller still builds and
  shows a window, it simply cannot be looked up by ID afterward. This is a
  deliberate no-op guard in `WindowRegistry`, not an error path.
- **Duplicate `windowID` across two live controllers**: `WindowRegistry`'s own
  documentation states its "one live controller per ID" assumption;
  registering a second controller under an ID already in use replaces the
  prior registry entry, so `controller(forID:)` returns only the most
  recently registered instance. The prior controller's window is unaffected
  by the replacement — the registry simply stops tracking it.
- **`fitWindow(toContentSize:)` called with a zero or negative dimension**:
  `fitWindow(toContentSize:)` guards against a non-positive width or height
  by returning immediately without applying any frame change; a degenerate
  size therefore never reaches `FrameCalculator.contentHuggingFrame` or
  AppKit's own `minSize` clamping (`minSize: windowSpec?.minSize ??
  window.minSize` is only ever threaded into a fit that actually runs).
- **Concurrent access from multiple threads**: Not applicable — the whole
  class is `@MainActor`-isolated, so the compiler prevents concurrent access
  from another thread; there is no runtime race to defend against.
- **Error/failure states**: Not applicable — none of this class's APIs are
  throwing or failable; `NSWindow` construction itself cannot fail with the
  parameters used here, so there is no error path to define.
- **Offline/disconnected state**: Not applicable — this class has no network
  dependency.
- **Unbounded settle-wait while the mouse button is held**: the debounced
  refit (see **move-refit-debounce**, **refit-drag-deferral**) reschedules
  itself indefinitely as long as `NSEvent.pressedMouseButtons` reports a
  held button, with no maximum retry count; a pathologically long drag
  defers the refit for the duration of the drag rather than firing early
  with a stale frame. This is a deliberate tradeoff (see Design Decisions),
  not an unhandled failure.
- **`configureWindow(_:)` mutates the delegate or frame**: Because the hook
  runs before delegate assignment and frame restoration (see
  **build-sequence**), any delegate-firing change `configureWindow(_:)`
  makes (e.g. resizing the window) is observed by `windowDidResize(_:)` like
  any other resize, including its `windowSpec.persistsFrame` save path.
