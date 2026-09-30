<!-- leaf: implement-composable-tabs/active-pane--test-vectors-part-2 · source: composable-tabs-active-pane.md -->

# ComposableTabsActivePane — Conformance Test Vectors (part 2)

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| CTA-51 | close-and-highlight-changes-dispatch-through-the-main-queue | `NSWindow.willCloseNotification` is posted, or `highlightActivePane` changes, while the run loop is tracking a mouse-down in `.eventTracking` mode | The active-id removal or backdrop repaint still applies before the tracking loop ends, because the handler is queued on `DispatchQueue.main` rather than `RunLoop.main` |
| CTA-52 | the-active-pane-uses-the-accent-outline-color | No pane in a window has claimed the active id (`activeNodeID(in:)` is `nil`); `applyTheme` runs for any pane in it | `layer.borderColor` equals `palette.projectPaneOutline` for every pane in the window, not the accent, even though `isInActivePane` reports `true` for a view in any of them |
