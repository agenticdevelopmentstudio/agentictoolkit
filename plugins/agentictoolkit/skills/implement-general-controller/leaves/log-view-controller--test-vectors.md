<!-- leaf: implement-general-controller/log-view-controller--test-vectors · source: log-view-controller.md -->

# Log View Controller

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| log-view-controller-001 | layout-stack | Load the view. | Toolbar, then a 1pt divider, then the log view, stacked top to bottom, filling the root view. |
| log-view-controller-002 | container-background | Load the view, inspect the root view's layer background. | Background color equals the current theme's `.windowBackground` role color. |
| log-view-controller-003 | minimum-content-size | Load the view with the default `minimumContentSize` (`600×400`), then attempt to resize the root view's frame to `300×200`. | The root view's effective width and height never fall below `600×400`. |
| log-view-controller-004 | fixed-toolbar-height | Load the view. | The toolbar view's height constraint equals `toolbarHeight` (`40pt` by default). |
| log-view-controller-005 | divider-below-toolbar | Load the view, inspect the divider view. | A 1pt-tall view filled with the `.divider` role color sits directly below the toolbar, pinned to the root view's leading and trailing edges. |
| log-view-controller-006 | log-view-fills-remaining-space | Load the view, resize the root view. | The hosted `LogView` fills the area below the divider, pinned to the root view's leading, trailing, and bottom edges. |
| log-view-controller-007 | leading-toolbar-items-rendered | Override `leadingToolbarItems()` to return two views, load the view. | Both views appear, in the order returned, in a horizontal stack pinned 12pt from the toolbar's leading edge. |
| log-view-controller-008 | leading-toolbar-items-overridable | Construct the base class (no override), load the view. | The leading stack contains zero subclass-supplied views. |
| log-view-controller-009 | trailing-toolbar-items-rendered | Override `extraTrailingToolbarItems()` to return one view, load the view. | That view appears before Pause, Clear, the status dot, and the status label, in that left-to-right order, in the trailing stack. |
| log-view-controller-010 | trailing-toolbar-items-overridable | Construct the base class (no override), load the view. | The trailing stack contains exactly Pause, Clear, the status dot, and the status label — no extra views. |
| log-view-controller-011 | lifecycle-start | Add the controller's view to a window and let it appear. | `controller.start()` is called exactly once. |
| log-view-controller-012 | lifecycle-stop | With the view appeared, remove it from the window (trigger `viewWillDisappear`). | `controller.stop()` is called exactly once. |
| log-view-controller-013 | indicator-state-refresh | Load the view, then set `controller.isConnected = false`, `controller.isPaused = true`, and `controller.lastError = "Disconnected"`, then invoke `controller.onStateChange?()`. | The status dot fills `.danger`, the status label text/tooltip read `Disconnected`, and the pause button title reads `Resume` — all three indicators reflect the new combined state. |
| log-view-controller-014 | indicator-theme-refresh | Load the view, then post `ThemeManager.didChangeNotification` — the notification the `ThemePaletteObserver` registered on `view` in `viewDidLoad` observes to re-apply the palette. | The status dot, status label, and pause button title are repainted using the new theme's role colors/fonts, still reflecting the current controller state. |
| log-view-controller-015 | connected-indicator | Set `controller.isConnected = true`, trigger a refresh. | Status dot color equals the `.success` role color; status label text and tooltip equal `Connected`. |
| log-view-controller-016 | error-indicator | Set `controller.isConnected = false` and `controller.lastError = "Disconnected"`, trigger a refresh. | Status dot color equals the `.danger` role color; status label text and tooltip equal `Disconnected`. |
| log-view-controller-017 | connecting-indicator | Set `controller.isConnected = false` and `controller.lastError = nil`, trigger a refresh. | Status dot color equals the `.warning` role color; status label text and tooltip equal `Connecting…`. |
| log-view-controller-018 | pause-button-title-tracks-pause-state | Set `controller.isPaused = true`, trigger a refresh; then set it to `false` and refresh again. | Pause button title reads `Resume`, then `Pause`. |
| log-view-controller-019 | pause-action | Click the pause button. | `controller.togglePause()` is called exactly once. |
| log-view-controller-020 | clear-action | Click the clear button. | `controller.clear()` is called exactly once. |
| log-view-controller-021 | coder-init-unavailable | Attempt to build the controller via `NSCoder`-based decoding (e.g. from a storyboard/XIB). | Compilation fails (unavailable), or a runtime `fatalError` occurs if the unavailability is bypassed. |
| log-view-controller-022 | default-start-size-floor | Construct the controller with default `minimumContentSize`, load the view, inspect the root view's initial frame. | Initial frame size is at least `900×600`. |
| log-view-controller-023 | status-dot-fixed-size | Load the view under a theme with an increased `sizeScale`. | The status dot's width and height constraints remain `8pt` each, unaffected by `sizeScale`. |
| log-view-controller-024 | connection-state-in-text | Trigger the connected, connecting, and error states in turn. | `statusLabel`'s text/tooltip read `Connected`, `Connecting…`, and the error string respectively — never the same string across states, and never conveyed by dot color alone. |
| log-view-controller-025 | lifecycle-start, lifecycle-stop | Add the controller's view to a window, let it appear, remove it from the window (disappear), then re-add it and let it appear again. | `controller.start()` is called twice and `controller.stop()` is called once, in appear → disappear → appear order. |
| log-view-controller-026 | default-start-size-floor | Override `minimumContentSize` to `1000×700` (larger than `900×600` on both dimensions), load the view, inspect the root view's initial frame. | Initial frame size equals `1000×700`, not `900×600`. |
