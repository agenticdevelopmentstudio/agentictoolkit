<!-- leaf: implement-general-view-2/session-watcher-activity-icon-view--edge-cases · source: session-watcher-activity-icon-view.md -->

# SessionWatcherActivityIconView

**Rules** (cite as `implement-general-view-2/session-watcher-activity-icon-view--edge-cases#<slug>`):

- `missing-unresolvable-sf-symbol` MUST — If NSImage(systemSymbolName:accessibilityDescription:) returns nil for the selected symbol name, renderGlyph() sets …
- `update-called-with-a-real-change-while-off-window` MUST — stopAnimation() still runs, but startAnimation() is gated on window != nil, so the new animation does not begin until …
- `rapid-repeated-update-calls-with-unchanged-values` MUST — Each call is a no-op past the initial equality guard — no redraw, no describeState(), no animation churn — which is …

## Edge Cases

- **Null/empty input**: Not applicable — `activity`
  (`SessionWatcher.SessionWatcherActivity`, a 3-case, non-optional enum) and
  `isSummarizing` (`Bool`) are both required, non-optional, typed
  constructor/`update` parameters; there is no null or empty variant for
  either to guard against.
- **Boundary values**: Not applicable — the component's only inputs are the
  fixed 3-case `activity` enum and a `Bool`; there is no numeric or
  range-bound input with a minimum/maximum boundary to test. The layout
  constant (13pt) and animation durations (0.7s, 1.1s) are literals in the
  source, not caller-configurable ranges.
- **Concurrent access**: The source defines no lock, queue, or explicit
  actor isolation of its own (unlike some sibling AppKit types, it carries
  no `@MainActor` attribute in this file). All of its mutable state
  (`activity`, `isSummarizing`, `tint`, `palette`) is touched only from
  `init`, `update(activity:isSummarizing:)`, and AppKit's own
  main-thread-invoked view-lifecycle callbacks (`viewDidMoveToWindow`,
  `viewDidChangeEffectiveAppearance`, `viewDidChangeBackingProperties`,
  `layout()`); nothing in the source itself prevents `update` from being
  called off the main thread, so the safety of concurrent access rests on
  AppKit's general view-mutation convention rather than a guarantee this
  file enforces.
- **Error states (dependency/network/filesystem failure)**: Not applicable
  — the source performs no I/O, network call, or dependency lookup of any
  kind; its only external input is the `activity`/`isSummarizing` values a
  caller passes in directly.
- **Offline/disconnected state**: Not applicable — the component performs
  no network operation of its own.
- **Missing/unresolvable SF Symbol**: If `NSImage(systemSymbolName:accessibilityDescription:)`
  returns `nil` for the selected symbol name, `renderGlyph()` sets
  `glyph.contents = nil` and returns — no fallback image, placeholder, or
  crash (MUST, per **unresolvable-symbol-fallback**). All four
  symbol names the source actually selects (`sparkles`,
  `arrow.triangle.2.circlepath`, `circle.fill`,
  `exclamationmark.circle.fill`) are real system symbols, so this path is
  unreached in normal operation but is still defined, source-observed
  behavior.
- **`update` called with a real change while off-window**: `stopAnimation()`
  still runs, but `startAnimation()` is gated on `window != nil`, so the new
  animation does not begin until the view is later added to a window
  (`viewDidMoveToWindow` re-renders and starts it then) (MUST, per
  **animation-restart-on-change** and
  **window-attach-animation-reinstall**).
- **Rapid repeated `update` calls with unchanged values**: Each call is a
  no-op past the initial equality guard — no redraw, no
  `describeState()`, no animation churn — which is what keeps a
  continuously-polled "working" spin visually smooth rather than restarting
  from zero on every poll (MUST, per **redundant-update-guard**).
