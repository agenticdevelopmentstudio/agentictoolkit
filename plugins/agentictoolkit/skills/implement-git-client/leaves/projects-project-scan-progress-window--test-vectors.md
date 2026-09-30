<!-- leaf: implement-git-client/projects-project-scan-progress-window--test-vectors · source: git-client-projects-project-scan-progress-window.md -->

# ProjectScanProgressWindow

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-project-scan-progress-window-001 | mainactor-isolation | Call `present()` or `finish()` from code that is not on the main actor and does not `await` the call. | Compilation fails, since `ProjectScanProgressWindow` is `@MainActor` and neither method is `nonisolated` or `async`. |
| git-client-projects-project-scan-progress-window-002 | fixed-panel-geometry-and-style | Construct `ProjectScanProgressWindow()`. | The instance's `window` is an `NSPanel` whose initial content size is 240×72 points and whose `styleMask` contains `.titled` and `.utilityWindow`. |
| git-client-projects-project-scan-progress-window-003 | panel-title | Construct `ProjectScanProgressWindow()`. | `window!.title` equals "Scanning". |
| git-client-projects-project-scan-progress-window-004 | floating-non-modal-presentation | Construct `ProjectScanProgressWindow()`. | `window!.isFloatingPanel` equals `true`; the class exposes no modal-presentation method to call instead. |
| git-client-projects-project-scan-progress-window-005 | deactivation-visibility | Construct `ProjectScanProgressWindow()`. | `window!.hidesOnDeactivate` equals `false`. |
| git-client-projects-project-scan-progress-window-006 | key-only-if-needed | Construct `ProjectScanProgressWindow()`. | `window!.becomesKeyOnlyIfNeeded` equals `true`. |
| git-client-projects-project-scan-progress-window-007 | centered-on-screen | Construct `ProjectScanProgressWindow()`. | `window!.frame` is centered on the screen that contains it, per `NSWindow.center()`. |
| git-client-projects-project-scan-progress-window-008 | automation-identifiers-assigned | Construct `ProjectScanProgressWindow()`. | The panel's accessibility identifier equals "project-scan.window" and the headline view's accessibility identifier equals "project-scan.headline". |
| git-client-projects-project-scan-progress-window-009 | initial-headline-text | Construct `ProjectScanProgressWindow()` and read the headline before calling `present()` or `finish()`. | The headline label's `stringValue` equals "Scanning for projects…". |
| git-client-projects-project-scan-progress-window-010 | initial-progress-bar-state | Construct `ProjectScanProgressWindow()`. | `bar.style` equals `.bar`, `bar.isIndeterminate` equals `true`, `bar.controlSize` equals `.small`, `bar.usesThreadedAnimation` equals `true`, `bar.minValue` equals `0`, and `bar.maxValue` equals `1`. |
| git-client-projects-project-scan-progress-window-011 | coder-initialization-unsupported | Call `ProjectScanProgressWindow(coder:)` with any `NSCoder`. | The process terminates via `fatalError` with the message "init(coder:) is not supported". |
| git-client-projects-project-scan-progress-window-012 | present-starts-animation-and-orders-front | Construct `ProjectScanProgressWindow()`, then call `present()`. | `bar`'s animation is running and the window becomes visible on screen without becoming the key window. |
| git-client-projects-project-scan-progress-window-013 | present-guards-missing-window | On an instance whose `window` has been set to `nil`, call `present()`. | No crash occurs; `bar.startAnimation` is not invoked and no window is ordered front. |
| git-client-projects-project-scan-progress-window-014 | finish-completes-progress-bar | Construct, call `present()`, then call `finish()`. | `bar.isIndeterminate` becomes `false` and `bar.doubleValue` equals `bar.maxValue` (`1`). |
| git-client-projects-project-scan-progress-window-015 | finish-updates-headline-text | Construct, call `present()`, then call `finish()`. | The headline label's `stringValue` equals "Scan complete". |
| git-client-projects-project-scan-progress-window-016 | finish-schedules-delayed-close | Call `finish()`, then observe the window before and after 1.0 second elapses. | Before 1.0 second, `window!.isVisible` is still `true`; after 1.0 second, `close()` has been called and `window!.isVisible` is `false`. |
| git-client-projects-project-scan-progress-window-017 | finish-close-closure-strong-capture | Call `finish()`, then immediately release every external strong reference to the instance. | After 1.0 second, the panel still closes itself; the instance is not deallocated early, since its own `asyncAfter` closure holds a strong reference to `self`. |
| git-client-projects-project-scan-progress-window-018 | finish-completes-progress-bar, finish-updates-headline-text, finish-schedules-delayed-close | Construct `ProjectScanProgressWindow()` and call `finish()` without ever calling `present()`. | The bar and headline update exactly as in vectors 014-015, and `close()` still fires after 1.0 second, even though the window was never shown. |
| git-client-projects-project-scan-progress-window-019 | present-starts-animation-and-orders-front | Call `present()` twice in succession. | `bar.startAnimation` is invoked again and the window is simply re-ordered front; no error and no duplicate window are produced. |
| git-client-projects-project-scan-progress-window-020 | finish-schedules-delayed-close | Call `finish()` twice in succession. | Two `asyncAfter` closures are scheduled; the first calls `close()` after 1.0 second, and the second's `close()` call on the already-closed window is a no-op that produces no crash. |
