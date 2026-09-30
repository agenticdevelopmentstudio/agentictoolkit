<!-- leaf: implement-git-client/projects-project-scan-progress-window--edge-cases · source: git-client-projects-project-scan-progress-window.md -->

# ProjectScanProgressWindow

**Rules** (cite as `implement-git-client/projects-project-scan-progress-window--edge-cases#<slug>`):

- `boundary-values` MUST — The progress bar's range is fixed at minValue 0 and maxValue 1, and the close delay is fixed at lingerAfterFinishing …
- `concurrent-access` MUST — ProjectScanProgressWindow is @MainActor, so all access to headline, bar, and window is serialized onto the main actor …
- `error-states` MUST — The only defensive check in the file is present()'s guard against a nil window; it MUST return silently, with no error …
- `out-of-order-calls` MUST — finish() MUST behave identically whether or not present() was called first — it updates bar and headline and schedules …

## Edge Cases

- **Null and empty input**: Not applicable — none of `init()`, `present()`,
  or `finish()` accept any parameter, so there is no null or empty input to
  handle (`ProjectScanProgressWindow.swift`).
- **Boundary values**: The progress bar's range is fixed at `minValue` `0`
  and `maxValue` `1`, and the close delay is fixed at `lingerAfterFinishing`
  (1.0 second); none of these are caller-supplied, so there is no boundary
  condition a caller can vary (`ProjectScanProgressWindow.swift`). MUST (this is the file's actual, unparameterized behavior).
- **Concurrent access**: `ProjectScanProgressWindow` is `@MainActor`, so all
  access to `headline`, `bar`, and `window` is serialized onto the main
  actor by the compiler. Calling `finish()` a second time before the first
  call's scheduled `close()` fires MUST queue a second `asyncAfter` closure
  that also calls `close()`; the second call lands on an already-closing or
  already-closed window, which is a harmless no-op
  (`ProjectScanProgressWindow.swift`). MUST.
- **Error states**: The only defensive check in the file is `present()`'s
  guard against a `nil` `window`; it MUST return silently, with no
  error signal of any kind, since the file declares no `throws` function, no
  `Result` type, and no other error-reporting mechanism
  (`ProjectScanProgressWindow.swift`). MUST.
- **Offline or disconnected state**: Not applicable —
  `ProjectScanProgressWindow.swift` makes no network call; its only work is
  updating local AppKit UI state and scheduling one local timer (whole
  file).
- **Cancellation**: The type provides no cancel operation of any kind; the
  type's doc comment states directly that the panel is "deliberately not
  modal and deliberately not cancellable"
  (`ProjectScanProgressWindow.swift`). This is the file's actual
  behavior, not an unresolved gap.
- **Out-of-order calls**: `finish()` MUST behave identically whether or not
  `present()` was called first — it updates `bar` and `headline` and
  schedules `close()` unconditionally; a panel that was never shown is
  simply closed once, while still hidden
  (`ProjectScanProgressWindow.swift`). MUST.
