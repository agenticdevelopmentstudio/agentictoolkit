<!-- leaf: implement-general-view-3/typing-indicator-view--edge-cases · source: typing-indicator-view.md -->

# TypingIndicatorView

## Edge Cases

- **Null/empty input**: Not applicable — the only initializer parameter is the inherited `frame: NSRect` from `NSView`; there is no optional or caller-supplied business input to guard against being null or empty.
- **Boundary values**: Not applicable in the sense of caller-facing constrained inputs — there are no numeric or string inputs. The view's own dimensional constants (48×28pt container, 7×7pt dots, 12pt/3.5pt corner radii, 4pt spacing) are fixed values set in `setup()`, not caller-supplied boundaries.
- **Concurrent access**: Not applicable — the class is `@MainActor`-isolated, so Swift's concurrency checking confines `dots`, `timer`, and `step` to main-actor access; the timer's fire callback re-enters via `MainActor.assumeIsolated`.
- **Error states**: Not applicable — construction, `startAnimating()`, `tick()`, and `removeFromSuperview()` are all synchronous with no throwing or failable call anywhere in the source.
- **Offline/disconnected state**: Not applicable — the source performs no networking of any kind.
- **Repeated calls to `startAnimating()` while already animating**: The source does not guard against this. Calling it a second time overwrites the `timer` property with a new `Timer.scheduledTimer(...)` without invalidating the previous one; because the prior timer was already added to the run loop independently of that property reference, it keeps firing. Both timers then call `tick()` against the same shared `step` counter, so the highlighted dot advances roughly twice as fast as intended (see vector typing-indicator-012). This is well-defined, traceable behavior, not a crash, but it is very likely unintended.
- **View hidden but not removed**: Setting `isHidden = true` while animating does not stop the timer — the only path that invalidates it is `removeFromSuperview()` (see **timer-invalidated-on-removal**). An indicator that is hidden rather than removed keeps its timer firing and its animation running invisibly.
- **Timer suspended during UI event tracking**: `Timer.scheduledTimer(withTimeInterval:repeats:block:)` schedules the timer on the current run loop's `.default` mode only (it is not added to `.common` modes). Per Apple's documented [RunLoop.Mode.default](https://developer.apple.com/documentation/foundation/runloop/mode-swift.struct/default) behavior, a timer scheduled this way is suspended while the main run loop is servicing a tracking loop elsewhere in the same app — an interactive window drag, a live/continuous slider drag, or a modal panel — so the pulse can visibly pause during that kind of input and resume once it ends.
